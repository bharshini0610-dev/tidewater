# NOT-DONE — deliberately left out, in priority order

What I would do with two more weeks, most important first.

1. **Replay the RCA against the real evidence bundle** (not supplied). Resolve every
   **[to confirm]** in `docs/RCA.md`, run `scripts/replay_alerts.py` on the Grafana CSVs and
   replace the estimates in `docs/SLO.md` E4 with the computed minutes.
2. **Credential rotation (RCA A7).** The DB password and an AWS key are in git history. Rotation
   happens outside the repo; history rewrite (`git filter-repo`) only after rotation, and it is optional.
3. **Canary releases with Argo Rollouts** (`AnalysisTemplate` on the same Prometheus queries
   as `verify.sh`). Today a bad release takes 100% of traffic for ~2 minutes before rollback.
4. **PgBouncer (k8s) / RDS Proxy (AWS)** in transaction mode, so the API can scale past 6 pods
   without re-doing the connection budget. Also a dedicated least-privilege DB role for the app
   (today the app uses the RDS master user on AWS) with IAM DB auth.
5. **Automated reconciliation** between the bank ledger and `payouts`, feeding the correctness SLI
   from the bank side as well as the DB side. **Confirm with the real bank** that it honours
   `Idempotency-Key` for at least the retry window.
6. **Mirror the alerts on AWS** (Amazon Managed Prometheus + Grafana, or CloudWatch alarms from
   EMF metrics) and connect Alertmanager to a real pager. Locally the alerts reach Alertmanager only.
7. **OIDC deploy role for GitHub Actions → AWS** and a pipeline stage that runs `terraform plan`
   per environment and ECS deploys by digest (promote the digest verified locally).
8. **Supply chain**: cosign keyless signing of the digest + admission verification (Kyverno), and
   an SBOM *gate* (the SBOM is produced and archived today, but not policy-checked). Pin the base
   image by digest via Dependabot (it is pinned by tag today).
9. **Redis**: AUTH token rotation automation, or ElastiCache IAM auth (removes the secret and its presence in state).
10. **Ingress**: move from ingress-nginx (in maintenance mode) to Gateway API; block `/metrics` at the edge with a dedicated route.
11. **Load test** (k6) to confirm HPA/connection-budget behaviour at max replicas and to size the
    worker (today the worker count is fixed at 2).
12. **Multi-region DR** for the payments database (cross-region read replica + tested restore runbook).
