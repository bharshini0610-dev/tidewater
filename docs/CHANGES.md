# CHANGES — every defect fixed, and why

The inherited state is commit `5135353` (a reconstruction, see README). Each row links to the
file that now contains the fix; `git log --oneline` shows one commit per fix, and each commit
message explains the reason.

## Runtime (Task B)

| # | Defect (inherited) | Impact on 14 Aug / risk | Fix | Why this fix |
|---|---|---|---|---|
| B1 | Liveness **and** readiness = `/healthz`, which ran `SELECT count(*) FROM settlements`; `timeoutSeconds: 1`, `failureThreshold: 1` | One slow query restarted a pod; a slow DB restarted **all** pods → restart storm | `/livez` + `/readyz` are process-local; startup probe; liveness 6 × 10 s; `/healthz/deps` for humans/alerts (`api.py`, `api-deployment.yaml`) | Restarting a pod never fixes a shared dependency (ADR-004) |
| B2 | SQLAlchemy `pool_size=5, max_overflow=10` per process | 60 conns/pod; 180–600 vs 100 allowed (RCA §5) | Pool 2 / overflow 0, `pool_timeout 2s`, `statement_timeout 5s`, `idle_in_transaction_session_timeout 10s`, `pool_pre_ping` (`db.py`, ConfigMap) | Bounded, fail-fast; see budget below |
| B3 | HPA max 10, unrelated to DB capacity | Scaling out made exhaustion worse | HPA 2..6, slow scale-down (`api-hpa.yaml`) | Max derived from the connection budget |
| B4 | Worker: BRPOP (job removed before work), re-push on any error, no idempotency key, no SIGTERM handling | **Double payments**, lost jobs on kill | Processing list + ack after success, reaper, capped retries + dead-letter, SIGTERM drain, claim-then-pay with UNIQUE key, bank `Idempotency-Key` (`worker.py`, `0009a/b`) | ADR-007; tested incl. the crash-between-bank-and-DB window |
| B5 | Worker `terminationGracePeriodSeconds` default 30 s | In-flight payouts killed on deploy/scale-down | 60 s (> worst-case job), heartbeat liveness, PDB (`worker-deployment.yaml`) | Drain must fit in the grace period |
| B6 | API: no preStop, `maxUnavailable` default | Requests dropped while endpoints update | `preStop sleep 10`, `terminationGracePeriodSeconds 45`, `maxUnavailable 0 / maxSurge 1`, PDB | Zero-downtime rollouts |
| B7 | DEBUG logs to `hostPath /var/log/settle`, no rotation; reconnect loop logged every failure | Node disk filled → **DiskPressure** → evictions | JSON to stdout, INFO; kubelet `container-log-max-size 10Mi × 3`; `ephemeral-storage` limits; eviction threshold; rate-limited error logging with exponential backoff (`logging_setup.py`, `k3d-cluster.yaml`) | Four independent layers: no single one can fill the disk |
| B8 | gunicorn `--timeout 5` while `/reports/daily` takes 6–9 s | gunicorn killed its own workers mid-request → 502 | `timeout 30`, `graceful_timeout 25`, keepalive 75 s (> nginx upstream keepalive) (`gunicorn.conf.py`) | Timeouts must be longer than the slowest legitimate request, and each hop's shorter than the one in front of it |
| B9 | Reports could occupy every DB connection | Slow reports starved `/settlements` | At most 1 report per process holds a connection; report statement_timeout 15 s | OLTP always has a connection |
| B10 | Dockerfile: `python:latest`, root, `COPY . .`, DB password in `ENV`, shell-form CMD | Unreproducible builds, secret in every image layer, PID 1 not gunicorn (SIGTERM lost) | Pinned slim base, multi-stage, uid 10001, explicit COPY + `.dockerignore`, no secrets, exec-form, pinned deps (`app/Dockerfile`) | Security + correct signal handling |
| B11 | `image: …:latest` in manifests | Rollback target ambiguous | Image set by the pipeline to `@sha256:` digest; `deploy.sh` refuses tags | Immutable artefact |
| B12 | **Secret manifest committed** (`deploy/k8s/config.yaml`, prod DB URL base64) | Credential disclosure | Deleted; secrets created at deploy time (`scripts/create-secrets.sh`); **rotation required** (RCA A7) | base64 is not encryption |
| B13 | Pods: no securityContext, SA token mounted, no resources | Container breakout blast radius, noisy neighbours | `runAsNonRoot`, read-only root FS, drop ALL caps, seccomp RuntimeDefault, no SA token, requests/limits | Baseline hardening |
| B14 | nginx `proxy_read_timeout 5s` | 504 on every report | 30 s (`ingress.yaml`, `settle.conf`) | Above report runtime + statement_timeout |
| B15 | nginx `proxy_next_upstream … non_idempotent`, 3 tries | Timed-out **POSTs re-sent** → duplicate settlement jobs | Retry only on connect `error`, 2 tries | Never replay a request that may have been processed |
| B16 | nginx access log to a file on the node; no request id; no limits | Disk growth; no correlation | JSON to stdout with `request_id`, `X-Request-ID` forwarded, body 1 MB, rate limit on writes, `server_tokens off`, `/metrics` denied externally | Observability + basic hygiene |
| B17 | No NetworkPolicy | Any pod could reach Postgres/Redis | Default-deny + explicit allows (`components/network-policy`) | Task F |

### Connection budget

```
total = (HPA_max + surge) × gunicorn_workers × (pool_size + max_overflow)      # API
      + (worker_replicas + surge) × 1 × (pool_size + max_overflow)            # worker
      + migration_job + exporters + superuser_reserved_connections + admin_headroom
      ≤ max_connections
```

| Local / k8s | | AWS prod (ECS, `deployment_maximum_percent 150`) | |
|---|---|---|---|
| API (6+1) × 4 × (2+0) | 56 | API ceil(6×1.5)=9 × 4 × 2 | 72 |
| worker (2+1) × 1 × 2 | 6 | worker 2×2 × 1 × 2 | 8 |
| migrate 1 + exporter 2 | 3 | migrate 1 | 1 |
| reserved 3 + admin 10 | 13 | rds reserved 3 + admin 10 | 13 |
| **total** | **78 ≤ 100** | **total** | **94 ≤ 100** |

Rollout surge counts: during a deploy at max scale the old and new pods coexist.

## Delivery (Task C)

| # | Defect | Impact | Fix |
|---|---|---|---|
| C1 | Migration 0008 renamed/retyped live columns and added a `NOT NULL` column without default | v1.7 broke mid-rollout; table locked; migration half-applied; rollback needed a down-migration | Expand/migrate/contract 0008a–c + contract step kept out of the pipeline (`migrations/README.md`, ADR-002) |
| C2 | Pipeline restarted pods **then** ran migrations via `kubectl exec` into an API pod | New code ran against the old schema; migration tied to a pod being replaced | Migration Job with the release digest runs first; rollout only if it succeeds (`scripts/deploy.sh`) |
| C3 | `echo "DB password is ${{ secrets.DB_PASSWORD }}"` | Secret in CI log (masking is best-effort, and it was the prod password) | No secrets echoed; generated secrets are `::add-mask::`ed; gitleaks gate on the tree |
| C4 | Built and pushed `:latest` in the deploy job; no scan | Different bits could reach each environment | Build once → OCI artifact (manifest digest) → pushed unchanged to the cluster registry; the same digest is used by scan, deploy, rollback and promotion; trivy HIGH/CRITICAL gate + SBOM |
| C5 | No tests/lint in the pipeline | — | ruff, pytest (with Postgres), hadolint, shellcheck, kubeconform, promtool, gitleaks |
| C6 | No verification, no rollback | 46 min outage, manual rollback | `scripts/verify.sh` + `scripts/rollback.sh`, triggered automatically |
| C7 | Self-hosted runner with standing cluster credentials; actions pinned to tags | Supply-chain and credential risk | GitHub-hosted runner, ephemeral cluster, actions pinned to commit SHAs, least-privilege `permissions:` per job, `concurrency` group |

## Infrastructure (Task D)

See `infra/terraform/REVIEW.md` (13 findings, impact and fix each).

## Observability (Task E)

| Gap | Fix |
|---|---|
| No metrics | Prometheus metrics for API (per route/status, latency histogram, pool usage), worker (queue depth, oldest job age, outcomes, duplicates prevented, duplicate gauge), Postgres exporter |
| No alerts | 5 alerts with runbook links (`observability/settle-rules.yaml`, `docs/RUNBOOK.md`) |
| Unstructured file logs | JSON logs to stdout; one `request_id` from nginx → API → Redis job → worker → bank |
