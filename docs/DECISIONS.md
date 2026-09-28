# Architecture Decision Records

Format: context · options · decision · consequences. Newest last.

---

## ADR-001 — Compute on AWS: ECS on Fargate (not EKS)

**Context.** Leadership wants settle on AWS this quarter. settle is two stateless containers
(API, worker) plus managed Postgres and Redis. The team that knew it has left; one DevOps
engineer now owns it. Staging must cost < USD 250/month.

**Options.**

| | ECS on Fargate | EKS (managed node groups or Fargate) |
|---|---|---|
| Control plane cost | 0 | ~USD 73/month per cluster → ~146 for staging+prod, ~30% of the staging budget alone |
| What we operate | Task definitions, services | Cluster upgrades every ~14 months, add-ons (CNI, CoreDNS, kube-proxy), node AMIs, ingress controller, autoscaler, IRSA/Pod Identity, Prometheus stack |
| Reuse of today's manifests | No — re-expressed in Terraform (`modules/ecs-service`) | Yes — kustomize base works as-is |
| Deploy safety | Deployment circuit breaker + CloudWatch-alarm rollback built in | Needs Argo Rollouts/Flagger or our pipeline script |
| Secrets | Native `secrets` from Secrets Manager into env | External Secrets Operator or CSI driver |
| Portability | AWS-specific | Kubernetes everywhere |

**Decision.** ECS on Fargate.

**Consequences.**
* (+) Nothing to patch below the container; the cost and effort match a 2-service system and a one-person team.
* (+) Rollback-on-alarm is a service setting (`deployment_circuit_breaker`, `alarms { rollback = true }`),
  wired to an ALB 5xx-ratio alarm in `modules/alb`.
* (−) Kubernetes manifests, PodDisruptionBudgets and NetworkPolicies do not carry over; their intent is
  re-implemented as ECS settings, security groups and deployment percentages. Two deployment
  targets exist until the local k3d environment is only used for development.
* (−) Prometheus-native alerts must be mirrored to CloudWatch (or Amazon Managed Prometheus) on AWS. Listed in NOT-DONE.
* Revisit if more services arrive (>~10) or a platform team starts offering a shared EKS.

---

## ADR-002 — Schema changes: expand → migrate → contract, forward-only, before rollout

**Context.** Migration 0008 renamed/retyped live columns during a rolling update and made
rollback require a down-migration (RCA root cause 1).

**Options.** (a) keep down-migrations and run them on rollback; (b) blue/green databases;
(c) expand/contract with backwards-compatible steps and no down-migrations.

**Decision.** (c). Each release's migration must work with the *previous* application version.
Migrations run as a Kubernetes Job (ECS RunTask on AWS) **before** the rollout, with the same
image digest, `lock_timeout = 3s`, `CREATE INDEX CONCURRENTLY`, batched backfills, and `NOT VALID` →
`VALIDATE` for constraints. Destructive "contract" steps live in `migrations/contract/`, are never
applied by the pipeline, and run only once the old version is outside the rollback window.
The release sequence is in `migrations/README.md`.

**Consequences.** (+) Rollback is always "redeploy the previous image", in seconds, without touching data.
(+) v1.7 and v1.8 run side by side (`test_v17_and_v18_can_run_side_by_side_after_expand`).
(−) A single logical change takes 2–4 releases, and a temporary sync trigger exists.
(−) Discipline is required. The runner refuses edited migrations, but reviewers still have to
reject non-additive SQL in `migrations/`.

---

## ADR-003 — Detecting a bad release and rolling back automatically

**Context.** The 14 Aug rollback was manual and took ~46 minutes. The brief requires automatic
detection and rollback in a local cluster.

**Options.** (a) `kubectl rollout status` only; (b) pipeline-driven verification (smoke tests + Prometheus
SLO queries scoped to the new ReplicaSet) followed by `kubectl rollout undo`; (c) Argo Rollouts canary with
an `AnalysisTemplate`; (d) on AWS: ECS circuit breaker + CloudWatch alarm rollback.

**Decision.** (b) for the local cluster/CI now, (d) on AWS. (c) is the next step (NOT-DONE #2).

**Why not (a).** The 1.9.1-rc regression passes readiness: pods start and `/readyz` is green.
Only behavioural checks catch it. See RUNBOOK "What caught 1.9.1-rc".

**Consequences.** (+) Simple, visible in the Actions log, no extra controller. (+) Verification only
looks at the new ReplicaSet (`pod_template_hash` label), so old pods' traffic cannot hide a regression.
(−) All traffic shifts before verification: a bad release affects 100% of requests for ~2 minutes
(soak + checks). A canary (c) would limit that to a slice. (−) The production pointer
(`deploy/releases/production.json`) is written by CI, so its history is the release history.

---

## ADR-004 — Health probes are process-local; dependency health is observed, not probed

**Context.** A liveness probe that queried Postgres turned a slow DB into a cluster-wide
restart storm (RCA root cause 2).

**Options.** (a) liveness process-only, readiness checks DB; (b) both process-local, DB health
exposed on `/healthz/deps` for dashboards/alerts; (c) keep DB in liveness with longer timeouts.

**Decision.** (b). Liveness = "can this process serve HTTP" (`/livez`). Readiness = "has this process
finished starting" (`/readyz`). Postgres/Redis health is on `/healthz/deps` and in metrics/alerts.

**Why not (a).** Postgres is shared by every pod. When it is slow, *all* pods fail readiness together,
the Service has zero endpoints, and nginx answers 503 for everything, including requests that
don't need the DB (`/version`, cached paths). It also hides the real problem behind "no endpoints".
With (b), the pods stay in rotation and DB-bound requests fail fast with `503 Retry-After`
(pool timeout 2 s, statement timeout 5 s). Metrics show exactly what is failing, and recovery is
automatic when the DB recovers. `make chaos-db` demonstrates this (restart count stays 0).

**Consequences.** (−) A pod with a *pod-local* broken DB connection (e.g. bad pool state) is not taken out
of rotation by readiness; `pool_pre_ping` and `pool_recycle` mitigate this. (−) The load balancer can't route
around the DB. That's correct, because there is only one DB.

---

## ADR-005 — Terraform state: S3 with native S3 locking (no DynamoDB)

**Context.** The draft had local state and no locking.

**Options.** (a) S3 + DynamoDB lock table (classic); (b) S3 with `use_lockfile = true` (Terraform ≥ 1.10);
(c) Terraform Cloud/HCP.

**Decision.** (b): one KMS-encrypted, versioned, TLS-only bucket per account (`bootstrap/`),
one key per environment (`settle/<env>/terraform.tfstate`).

**Consequences.** (+) One fewer resource and IAM grant. DynamoDB-based locking is deprecated in recent Terraform releases.
(−) Requires Terraform ≥ 1.10 everywhere (pinned via `required_version`). (−) The bucket is
bootstrapped with local state once. That's documented in `bootstrap/main.tf`.

---

## ADR-006 — Database connections: small fixed pools and HPA capped by a budget (PgBouncer later)

**Context.** 600 potential connections against `max_connections = 100` (RCA §5).

**Options.** (a) raise `max_connections`; (b) small pools with no overflow, fail-fast timeouts, and replica
caps derived from a formula; (c) PgBouncer / RDS Proxy in transaction mode.

**Decision.** (b) now, (c) next. Formula in `docs/CHANGES.md#connection-budget`, enforced in the
ConfigMap comments, the HPA max, and a Terraform `check` block for AWS.

**Consequences.** (+) Safe at any replica count the HPA allows, including rollout surge.
(−) The API can only scale to 6 pods. A traffic increase beyond that needs (c) first, which is
the documented trigger to do it.

---

## ADR-007 — Exactly-once payout effect: claim-then-pay with a shared idempotency key

**Context.** 37 double payments (RCA §6). The queue can deliver a job more than once (retries,
reaper, duplicate POSTs), so exactly-once *delivery* is not achievable.

**Decision.** Make the *effect* idempotent. The key is `merchant_id:settlement_date`:
1. `INSERT … ON CONFLICT DO NOTHING` claims the payout row (UNIQUE index) **before** the bank call;
2. the same key is sent as `Idempotency-Key` to the bank;
3. the row is marked `sent` after the bank confirms, and the job is acknowledged only then.

A retry at any point either finds `sent` (skip) or re-calls the bank with the same key (the bank returns
the original payout).

**Why this is operability, not business logic.** The settlement *amount* and *who is paid*
are unchanged. What changed is delivery semantics under failure and retries, which is exactly
what "deploys and scale-downs must not lose or duplicate in-flight jobs" asks for.

**Consequences.** (+) Duplicates are impossible at the DB level and rejected by the bank. (+) A
`settle_duplicate_payouts` gauge proves it continuously. (−) One legitimate second payout for the
same merchant/date (e.g. a correction) now needs an explicit new key, which is a product decision.
(−) Requires the real bank API to honour idempotency keys; this must be confirmed with the bank (NOT-DONE).

---

## ADR-008 — Where the pipeline runs: GitHub-hosted runners with an ephemeral k3d cluster

**Context.** The brief allows a real GitHub repo or `act`. The inherited pipeline used a self-hosted
runner with standing cluster credentials.

**Options.** (a) self-hosted runner on a laptop with access to a long-lived cluster; (b) `act` locally;
(c) GitHub-hosted runners that create a fresh k3d cluster per run, seeded with the current production digest.

**Decision.** (c). It runs on **real GitHub Actions**, not `act`.

**Consequences.** (+) No long-lived cluster credentials anywhere. Every run is reproducible and
starts from "what production runs now". (+) Anyone can re-run the demo from the Actions tab.
(−) Each run spends ~10 min creating the cluster and platform. (−) A real environment would use
the same scripts against a persistent cluster with OIDC-issued credentials. The scripts are
cluster-agnostic (`kubectl` context), so only the job's setup steps change.
