# RCA — settle incident, 14 Aug 2026 (v1.8.0)

**Status:** draft for review · **Format:** blameless · **Author:** DevOps (settle owner)

> **What this RCA is built on.** The brief describes an evidence bundle
> (`incident-2026-08-14/`: nginx, API, worker and Postgres logs, `kubectl` output,
> `df`/`dmesg`, Grafana CSVs, CI log). **That bundle was not supplied with the assignment,
> and neither was the repository.** This RCA therefore cites:
>
> * **[B]** facts stated in the brief (times, symptoms, 37 merchants, `max_connections=100`,
>   4 gunicorn workers, `/reports/daily` 6–9 s);
> * **[R]** the inherited repository as reconstructed in commit `5135353`
>   (`git show 5135353:<file>` shows every line cited below);
> * **[X]** reproductions I ran myself (tests and pipeline runs in this repo).
>
> Every claim that would normally be proven by a log line is marked **[to confirm]** with the
> exact query to run against the bundle. When the bundle arrives, those are the first
> things to check; the conclusions below are hypotheses until then.

## 1. Summary

v1.8.0 shipped a schema change (migration 0008) that renamed and rewrote the `settlements`
and `payouts` tables in place. The old pipeline restarted all pods **before** running that migration
from inside an API pod. The table rewrite locked `settlements`. The liveness probe queried that table
with a 1-second timeout and a failure threshold of 1, so every API pod failed liveness at once
and the kubelet restarted them all. While restarting, pods reopened
oversized connection pools that together exceed Postgres `max_connections`. That kept the database saturated and the probes failing:
a self-sustaining restart loop. Customers saw 502/504 from 14:05 to 14:51.

The worker removed jobs from the queue before processing them and put them back on *any*
error, including after the bank had already paid. The bank call carried no idempotency key.
Payouts that succeeded at the bank but failed to record (the DB was locked or out of
connections), or whose pod was killed mid-job, were sent again: **37 merchants were paid
twice**. Both services wrote DEBUG logs to a host directory with no rotation, and the
worker logged every failed reconnect in a tight loop. That filled the node's disk (DiskPressure) and
evictions killed even more in-flight work.

Nothing alerted. Finance found the double payments.

## 2. Impact

| | |
|---|---|
| Customer-facing errors | 14:05–14:51 (46 min), intermittent 502/504 on all API routes **[B]** |
| Money | 37 merchants paid twice **[B]**; amount = Σ duplicate payout rows **[to confirm: `SELECT merchant_id, settlement_date, count(*), sum(amount) FROM payouts GROUP BY 1,2 HAVING count(*)>1`]** |
| Platform | API pods in restart loop, one node DiskPressure **[B]** |
| Detection | Finance reconciliation, after the event **[B]** — no alert fired |

## 3. Timeline (UTC)

The brief does not give a time zone. I assume all times are UTC. **[to confirm: normalise nginx (`$time_local`), Postgres (`log_timezone`) and kubectl (UTC) timestamps before merging]**

| Time | Event | Evidence |
|---|---|---|
| 14:02 | Pipeline for v1.8.0 starts: `kubectl apply` + **`rollout restart`** of API and worker, *then* migrations via `kubectl exec deploy/settle-api -- psql …` | [B] deploy time; [R] `.github/workflows/deploy.yml:13-15`; [to confirm: CI run log] |
| 14:02–14:03 | New v1.8 pods start while the schema is still 0007. v1.8 code reads `amount_cents`, which does not exist yet, so its requests fail | [R] `app/settle/api.py:32` vs `migrations/0007`; [to confirm: API log `UndefinedColumn amount_cents`] |
| ~14:03 | 0008 runs: `RENAME amount → amount_cents` breaks the v1.7 pods still serving. `ALTER … TYPE bigint` rewrites `settlements` under an **ACCESS EXCLUSIVE** lock. `ADD COLUMN currency text NOT NULL` fails on a non-empty table, leaving the migration **half-applied** (psql `-f` without `--single-transaction`) | [R] `migrations/0008_amount_cents.sql:2-4`, workflow line 15; [to confirm: Postgres log `ERROR: column "currency" … contains null values`, `LOG: process … still waiting for AccessExclusiveLock`] |
| 14:03–14:05 | `/healthz` runs `SELECT count(*) FROM settlements` and blocks behind the lock. Liveness timeout is 1 s and failureThreshold is 1, so every pod fails liveness | [R] `deploy/k8s/api.yaml:21-25`, `app/settle/api.py:21-24`; [to confirm: `kubectl describe` "Liveness probe failed: … context deadline exceeded"] |
| 14:05 | First customer 502/504s; kubelet restarts API pods cluster-wide | [B]; [to confirm: nginx access log first 502, events `Killing`, `BackOff`] |
| 14:05–14:51 | **Restart loop.** Each restarted pod opens up to 60 connections (see §5), so Postgres returns `too many clients` and `/healthz` keeps failing. HPA scales towards 10 on start-up CPU, which makes it worse | [R] `app/settle/db.py:5`, `api.yaml:53`; [to confirm: Postgres `FATAL: sorry, too many clients already`, HPA events] |
| 14:05–14:51 | Background 504s on `/reports/daily` (6–9 s) from nginx `proxy_read_timeout 5s`, and 502s from gunicorn `--timeout 5` killing its own workers mid-report | [B] report latency; [R] `ingress.yaml:7`, `Dockerfile:7` |
| During | Worker: DB errors → `log.exception` + re-push, with no backoff. DEBUG logs pile up in `hostPath /var/log/settle` | [R] `worker.py:34-43`, `api.yaml:34`; [to confirm: node `df -h` growth, worker log volume per minute] |
| ~? | Node reports **DiskPressure** → kubelet evicts pods (incl. workers mid-payout) | [B]; [to confirm: `dmesg`/events `Evicted`, `DiskPressure`] |
| ? – 14:51 | Previous team rolls back manually; errors stop at 14:51 | [B] |
| Later | Finance finds 37 merchants paid twice | [B] |

## 4. Root causes and contributing factors

**Root cause 1 — a non-backwards-compatible schema change was applied during a rolling
update, by a pipeline that ran it in the wrong order.** 0008 renamed and retyped live columns
(`0008_amount_cents.sql:2-3`). Old and new pods cannot both work against either schema, and the
migration ran *after* the new pods had started (`deploy.yml:14-15`). The rewrite held an ACCESS
EXCLUSIVE lock on the busiest table.

**Root cause 2 — the liveness probe depended on the database.** `/healthz` queried
`settlements` (`api.py:24`) with `timeoutSeconds: 1, failureThreshold: 1` (`api.yaml:22-25`).
A slow or locked database therefore made every pod "dead" at the same moment. The kubelet restarting all of them
turned a degraded database into a full outage and kept it there.

**Root cause 3 — payouts were not idempotent and jobs were not acknowledged safely.** See §6.

Contributing factors:

| # | Factor | Evidence |
|---|---|---|
| C1 | Connection pools sized with no relation to `max_connections` (§5) | [R] `db.py:5`, `api.yaml:53` |
| C2 | nginx `proxy_read_timeout 5s` and gunicorn `--timeout 5` below the 6–9 s report | [R] `ingress.yaml:7`, `Dockerfile:7`; [B] |
| C3 | nginx retried **POST** requests (`non_idempotent`) on timeout, which enqueued the same settlement more than once | [R] `ingress.yaml:8`, `settle.conf:10` |
| C4 | DEBUG file logging on a hostPath with no rotation; error loop with no backoff | [R] `api.py:14`, `worker.py:12,42-43`, `api.yaml:34` |
| C5 | No post-deploy verification or automatic rollback; manual rollback took ~46 min | [R] `deploy.yml` (no verify step) |
| C6 | No alerting on errors, restarts, DB saturation or payout correctness | [B] detected by finance |
| C7 | Worker had no SIGTERM handling and the default 30 s grace period | [R] `worker.py` (no signal handler) |
| C8 | `:latest` images (the rollback target is ambiguous) and a DB password baked into the image, the Secret manifest, the Terraform draft and the CI log | [R] `api.yaml:16`, `Dockerfile:6`, `config.yaml:18`, `deploy.yml:10`, `infra/terraform/main.tf:3-4,32` |

## 5. Capacity arithmetic

Inherited settings: gunicorn **4** workers per pod [B], SQLAlchemy `pool_size=5,
max_overflow=10` per worker process [R `db.py:5`], HPA `minReplicas 3 / maxReplicas 10`
[R `api.yaml:52-53`], worker Deployment 2 replicas with the same engine.

```
per API process     = pool_size + max_overflow           = 5 + 10 = 15
per API pod         = 4 processes × 15                   = 60
at minReplicas 3    = 3 × 60                             = 180
at maxReplicas 10   = 10 × 60                            = 600
workers             = 2 × 15                             = 30
Postgres            = max_connections 100 − superuser_reserved_connections 3 = 97 usable
```

Even at the **minimum** replica count, potential demand (180 + 30 = 210) was more than 2× what
Postgres allows. In normal operation it stayed hidden because most requests return their
connection within milliseconds. Once queries blocked on the migration lock, every request
held its connection, pools grew to `max_overflow`, and the ~97 slots ran out. That produced
`too many clients`, which failed `/healthz`, which triggered restarts, which reconnected everything at once.
**[to confirm: `pg_stat_activity` count in the Grafana CSV reaching ~97–100 before 14:05.]**

New budget (formula in `docs/CHANGES.md#connection-budget`): 7 API pods (HPA max 6 + 1
surge) × 4 × (2 + 0) = 56; worker 3 × 1 × 2 = 6; migrate 1, exporter 2, reserved 3, admin
10 → **78 ≤ 100**. On AWS the same formula is enforced by a Terraform `check` block.

## 6. How 37 merchants were paid twice

The inherited worker loop (`git show 5135353:app/settle/worker.py`):

```python
_, raw = r.brpop(QUEUE)          # 1. job REMOVED from Redis before any work
process(job):
    amount = SELECT …            # 2.
    httpx.post(bank/payouts)     # 3. bank pays — no Idempotency-Key
    INSERT INTO payouts …        # 4. record it
except Exception:
    r.lpush(QUEUE, raw)          # 5. ANY failure, including step 4, re-queues the job
```

The failure window is **between 3 and 4**. During the incident, step 4 failed for payouts whose
bank call had just succeeded:

* `INSERT INTO payouts (… amount_cents …)` failed because 0008 had half-renamed columns, the
  table was locked, or there were no free connections → exception → job re-queued → the next
  attempt paid again (**duplicate**);
* a pod was killed between 3 and 4 (liveness restart, DiskPressure eviction, the manual
  rollback's pod replacement — no SIGTERM handling). BRPOP had already removed the job, so it
  was lost, **unless** the same settlement had also been enqueued twice by nginx
  re-sending a timed-out `POST /settlements` to a second pod (C3), in which case the copy
  paid again.

Nothing downstream stopped it: `payouts` had no unique constraint on (merchant, date) and the
bank API received no idempotency key. **[to confirm: for each of the 37 merchants, the worker
log should show two `POST /payouts` with the same merchant/date, the first followed by a DB
exception; count distinct merchant/date pairs with >1 bank call = 37.]**

**Fix (reproduced in tests [X]):** jobs move atomically to a per-worker processing list and are
acknowledged only after the payout is recorded. A payout row is *claimed* under a UNIQUE
`idempotency_key = merchant:date` **before** the bank call. The same key is sent to the bank,
so a retry after "bank paid, DB not updated" is answered with the original payout.
`test_crash_after_bank_paid_before_db_update_does_not_pay_twice` reproduces exactly this
window and passes. `docs/evidence/local-e2e-idempotency.txt` shows three requests for the same
merchant/date resulting in one payment.

## 7. Things that looked alarming and why they are not (or not yet shown to be) causal

The brief warns that some evidence is noise. Without the bundle, I can't name specific log
lines. These are the checks I will apply to each alarming item, and what I expect them to rule out:

| Candidate | Test | Expected verdict |
|---|---|---|
| Errors on `/reports/daily` (504) | Present on days **before** 14 Aug too? (timeout 5 s < 6–9 s runtime) | Pre-existing, chronic. Contributing noise, not the trigger. Fixed anyway. |
| DiskPressure / evictions | Did the first 502 (14:05) happen **before** the first DiskPressure event? | Consequence of the error loop, not its cause; it amplified job loss. |
| HPA scaling to max | Scaling started after restarts began? (CPU spikes on start-up) | Amplifier of connection exhaustion, not a trigger. |
| CI log warnings (e.g. action deprecation, `latest` tag) | Would the same warnings appear on successful deploys? | Hygiene only. The important CI line is the step ordering, not the warnings. |
| Anything in `dmesg` not related to disk (e.g. OOM of an unrelated process, NIC messages) | Is the process/pod on settle's request path? Is the timestamp inside 14:02–14:51? | Not causal unless it is on the path and inside the window. |
| Postgres `checkpoints are occurring too frequently` | Typical side effect of the table rewrite | Symptom of 0008, not an independent cause. |

## 8. Why detection took so long

No alert on error rate, pod restarts, DB connections or payout correctness existed, and logs
were files on a node. Section E4 of `docs/SLO.md` shows the five new alerts against the brief's
timeline. The restart and burn-rate alerts would have fired **within ~5–7 minutes of 14:02**,
and the duplicate-payout alert on the first duplicate, instead of at finance reconciliation.

## 9. Action items

| ID | Action | Owner (role) | Priority | Status |
|---|---|---|---|---|
| A1 | Replace 0008 with expand/migrate/contract; migrations run as a Job **before** rollout; contract steps manual | DevOps + settle dev | P0 | Done — `migrations/`, `scripts/deploy.sh` |
| A2 | Liveness/readiness must not depend on Postgres/Redis | DevOps | P0 | Done — `api.py`, `api-deployment.yaml` |
| A3 | Idempotent payouts: processing list + ack, SIGTERM drain, unique idempotency key, bank Idempotency-Key | settle dev | P0 | Done — `worker.py`, `0009*`, tests |
| A4 | Reconcile and recover the 37 double payments with the bank; confirm the list from the DB query in §2 | Finance + settle lead | P0 | Open |
| A5 | Connection budget: pools 2/0, pool/statement timeouts, HPA max 6; later PgBouncer/RDS Proxy | DevOps | P0 | Done (PgBouncer in NOT-DONE) |
| A6 | Post-deploy verification + automatic rollback in CI | DevOps | P0 | Done — `.github/workflows/deploy.yml`, `scripts/verify.sh` |
| A7 | **Rotate** credentials exposed in git history: DB password (Secret manifest, Dockerfile, Terraform, CI log), AWS access key in the Terraform draft. Purge the CI log | Security + DevOps | P0 | Open — cannot be done from the repo |
| A8 | Alerts: burn rate, restarts, DB connections, duplicate payouts, stale settlements, with runbooks | DevOps | P1 | Done — `observability/settle-rules.yaml`, `RUNBOOK.md` |
| A9 | Logs to stdout as JSON with request_id; kubelet log rotation; rate-limited error logging with backoff | DevOps | P1 | Done |
| A10 | nginx: timeouts above the slowest request, never retry POST | DevOps | P1 | Done |
| A11 | Replay this RCA against the real evidence bundle; resolve every **[to confirm]** | DevOps | P1 | Open — bundle not received |
| A12 | Daily automated reconciliation (bank ledger vs `payouts`) feeding `settle_duplicate_payouts` | settle dev + Finance | P2 | Open (NOT-DONE) |
