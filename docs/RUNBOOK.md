# settle RUNBOOK

## Quick reference

| I want to… | Command |
|---|---|
| Bring up everything locally (k3d + ingress + Prometheus/Grafana + settle 1.9.0) | `make up` |
| Build, deploy and verify a release locally (auto-rollback on failure) | `make release RELEASE=1.9.0` · `make release RELEASE=1.9.1-rc` |
| Deploy through the real pipeline | GitHub → Actions → **deliver** → *Run workflow* → pick `release` |
| Roll back by hand | `make rollback` (below) |
| Open Grafana / Prometheus | `make grafana` (prints the generated password) · `make prometheus` |
| Inject 3 s DB latency / remove it | `make chaos-db` · `make chaos-db-off` |
| Show an alert firing end-to-end | `make alert-demo` |

Tools: docker, k3d ≥ 5.7, kubectl, helm, kustomize, python3. On Windows use WSL2.

---

## Deploy

### Through the pipeline (normal path)
1. Merge to `main` (or *Run workflow* with `release`).
2. The pipeline: lint/test → Terraform checks → **build once** (pushes `ghcr.io/<owner>/settle-api`,
   records the digest) → trivy scan → k3d cluster seeded with the **current production digest**
   (`deploy/releases/production.json`) → migration Job (expand-only) → rollout by digest →
   **post-deploy verification** → promote *or* **automatic rollback**.
3. Read the run's **Summary** tab: build digest, scan result, verification table, rollback table.
   Evidence (logs, screenshots) is attached as an artifact and pushed to the `evidence` branch.

### What caught 1.9.1-rc
The RC's pods started and passed readiness, so `kubectl rollout status` was **green**.
Verification then failed on two independent signals, both scoped to the new ReplicaSet:
* **smoke test**: `GET /settlements` → HTTP 500 (the RC reads a column that no migration created);
* **SLO gate**: 5xx ratio of the new pods over 2 min ≫ 1% (Prometheus,
  `settle_http_requests_total{pod_template_hash=<new>}`).

The pipeline ran `kubectl rollout undo`, waited for the previous ReplicaSet (1.9.0), re-ran
verification against 1.9.0 (pass), and failed the run with *"Release 1.9.1-rc rejected"*. No
schema change needed undoing because every migration is backwards compatible (ADR-002).

## Roll back manually

**Kubernetes (local / any cluster):**
```bash
kubectl -n settle rollout history deployment/settle-api      # change-cause shows version + digest
kubectl -n settle rollout undo deployment/settle-api          # or: --to-revision=<n>
kubectl -n settle rollout undo deployment/settle-worker
kubectl -n settle rollout status deployment/settle-api --timeout=180s
scripts/verify.sh <previous-version>
```
Then **revert the promotion commit** of `deploy/releases/production.json` so that the next
pipeline run seeds the correct version.

**Never** run a down-migration. If a release must be rolled back, its schema is by construction
compatible with the previous version. If a *contract* migration was run too early, stop and
restore the table from the latest snapshot/PITR, and escalate.

**AWS (ECS):** `aws ecs update-service --cluster settle-<env> --service settle-<env>-api
--task-definition <previous revision>` (same for `-worker`). The circuit breaker and the
`settle-<env>-api-5xx` alarm do this automatically during a failed deployment.

## Chaos: slow database (Task F)
`make chaos-db` adds 3000 ms to every Postgres round trip (toxiproxy). Expected, graceful behaviour:
DB-bound requests return `503 Retry-After: 5` within ~2 s (pool timeout) or complete slowly.
`/livez`, `/readyz` and `/version` stay fast, **API restart count stays 0**, the worker backs off
and logs at most once per 30 s, and `SettleApiErrorBudgetBurn` fires. `make chaos-db-off` recovers
without intervention.

## Finding one request everywhere
Every log line is JSON with `request_id` (nginx `$req_id` → API → Redis job → worker → bank header).
```bash
RID=<id from the X-Request-ID response header>
kubectl -n ingress-nginx logs deploy/ingress-nginx-controller | grep "$RID"
kubectl -n settle logs -l app=settle-api --prefix | grep "$RID"
kubectl -n settle logs -l app=settle-worker --prefix | grep "$RID"
```

---

# Alerts

Each alert's `runbook_url` points at one of the sections below.

## SettleApiErrorBudgetBurn
**Meaning.** Over both the last 5 min and 1 h, more than 7.2% of API requests (excluding
`/reports/daily`) were 5xx or slower than 500 ms. That is 14.4× the rate allowed by the 99.5% SLO:
2% of the monthly budget per hour.
**Check first.** Grafana *settle — service overview*: requests by status, p99, "503s from DB fail-fast",
DB connections panel. `kubectl -n settle get pods`, recent `rollout history`.
**Likely causes → action.**
* Started right after a deploy → roll back (above); the pipeline should already have done it — find out why it didn't.
* `settle_db_unavailable_total` rising, DB connections high or `/healthz/deps` shows postgres error → DB slow/locked:
  `SELECT pid, now()-query_start, wait_event_type, query FROM pg_stat_activity ORDER BY 2 DESC LIMIT 20;` look for a lock holder
  (migration? report?) and cancel with `pg_cancel_backend(pid)` if safe.
* Latency only, no 5xx → CPU throttling (`kubectl top pods`), HPA at max 6? Do **not** raise the HPA max without
  re-doing the connection budget.
**Escalate** to the settle dev on-call if not mitigated in 15 min; to the DB owner for DB-side causes.

## SettlePodsRestarting
**Meaning.** A settle pod restarted more than twice in 10 minutes.
**Check.** `kubectl -n settle describe pod <pod>` (Last State, Reason, Events); `kubectl -n settle logs <pod> --previous`.
**Likely causes → action.**
* `OOMKilled` → memory leak or oversized report: raise the limit temporarily, open a bug.
* Liveness failures → the process is truly hung (liveness no longer depends on the DB). Capture `py-spy dump` if possible and roll back if it began with a deploy.
* `CrashLoopBackOff` right after a deploy → roll back.
* Evicted / DiskPressure → check node disk (`kubectl describe node`), find the pod writing heavily (should not be possible: stdout + rotation + ephemeral limits). If it is, that is a new defect.

## SettlePostgresConnectionsHigh
**Meaning.** More than 80% of `max_connections` in use for 2 min — the precursor of the 14 Aug exhaustion.
**Check.** `SELECT usename, application_name, state, count(*) FROM pg_stat_activity GROUP BY 1,2,3 ORDER BY 4 DESC;`
`application_name` includes the settle version, so you can see which version holds the connections.
**Action.** Identify idle-in-transaction or long queries and cancel them. Check that API replicas
≤ HPA max and nobody scaled by hand. Check for a non-settle client (ad-hoc psql, BI tool) and ask them to disconnect.
**Do not** raise `max_connections` or pool sizes during an incident. Follow the connection budget (CHANGES.md).

## SettleDuplicatePayout
**Meaning.** In the last 24 h some merchant/date has more than one `payouts` row. This should be
impossible (UNIQUE idempotency key), so **treat it as a money incident: page immediately**.
**Action.**
1. Stop the bleeding: `kubectl -n settle scale deploy/settle-worker --replicas=0` (jobs wait safely in Redis).
2. List them: `SELECT merchant_id, settlement_date, count(*), array_agg(id), array_agg(bank_ref) FROM payouts
   WHERE created_at > now()-interval '24 hours' GROUP BY 1,2 HAVING count(*)>1;`
3. Check with the bank whether each `bank_ref` was actually paid (the bank's idempotency should have collapsed them).
4. Inform Finance with the list. Do not restart the worker until the cause is understood (e.g. rows written without
   `idempotency_key` by an old version or a manual script).

## SettleSettlementsStale
**Meaning.** The oldest queued or in-flight settlement job has waited > 15 min (freshness SLO), or no worker is up.
**Check.** Grafana "Queue depth and in-flight", "Jobs by outcome"; `kubectl -n settle get pods -l app=settle-worker`;
`redis-cli LLEN settle:jobs`, `LLEN settle:jobs:dead`, `KEYS settle:processing:*`.
**Likely causes → action.**
* No worker running / crash-looping → see SettlePodsRestarting.
* Bank API failing (`jobs_total{outcome="retried"}` rising) → check the bank status page; jobs retry 5× then dead-letter.
* Jobs in `settle:jobs:dead` → inspect `last_error`; after fixing the cause, re-queue:
  `redis-cli LMOVE settle:jobs:dead settle:jobs RIGHT LEFT` (safe: payouts are idempotent).
* Processing list of a dead worker not drained → the reaper runs every 30 s; if it doesn't, restart one worker.
