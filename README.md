# settle — Project Tidewater

Daily merchant settlement service (`settle-api` + `settle-worker`), made safe to operate after
the 14 Aug v1.8.0 incident.

> **Reconstruction notice.** No source repository, evidence bundle or pre-built images came
> with the brief. Commit `5135353` is therefore a **reconstruction** of the inherited
> repository from the facts in the brief. Its defects are the ones the incident symptoms
> imply. Every later commit is one fix, with the reason in the commit message.
> `settle-api:1.9.0` and `1.9.1-rc` are built by the pipeline (`images/README.md`).

## Run it

```bash
make up                         # k3d cluster, ingress-nginx, Prometheus/Grafana, settle 1.9.0 (verified)
make release RELEASE=1.9.1-rc   # deploy the bad RC -> verification fails -> automatic rollback to 1.9.0
make alert-demo                 # 3 s DB latency -> SettleApiErrorBudgetBurn fires, pods do not restart
make grafana                    # dashboard "settle — service overview"
make down
```

The same flow runs on **GitHub Actions** (real runners, not `act`): *Actions → deliver → Run
workflow*, choose `1.9.0` or `1.9.1-rc`. Evidence of every run is on the `evidence` branch.

## Where things are

| Brief item | Location |
|---|---|
| Task A — RCA | [`docs/RCA.md`](docs/RCA.md) |
| Task B — runtime fixes | `app/`, `deploy/k8s/`, `deploy/nginx/`, [`docs/CHANGES.md`](docs/CHANGES.md) (incl. connection-budget formula) |
| Task C — pipeline, migrations, rollback | [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml), `scripts/`, [`migrations/README.md`](migrations/README.md) |
| Task D — AWS IaC | `infra/terraform/` · [`REVIEW.md`](infra/terraform/REVIEW.md) · [`COST.md`](infra/terraform/COST.md) · `check.sh` |
| Task E — observability | `observability/`, [`docs/SLO.md`](docs/SLO.md) (SLOs, alerts, 14 Aug replay) |
| Task F — chaos-db, NetworkPolicy, SBOM | `scripts/chaos-db.sh`, `deploy/k8s/components/network-policy/`, SBOM in the scan job |
| ADRs | [`docs/DECISIONS.md`](docs/DECISIONS.md) (8 ADRs; ADR-001 = ECS vs EKS) |
| Runbook | [`docs/RUNBOOK.md`](docs/RUNBOOK.md) |
| Not done | [`docs/NOT-DONE.md`](docs/NOT-DONE.md) |
| AI usage | [`docs/AI-USAGE.md`](docs/AI-USAGE.md) |

## Layout

```
app/                 FastAPI API, worker, mock bank, migration runner, tests, Dockerfile
migrations/          expand/contract SQL (contract/ is never applied automatically)
deploy/k8s/          kustomize base + local overlay + network-policy component + migration Job
deploy/nginx/        plain-nginx equivalent of the ingress settings
observability/       kube-prometheus-stack values, PodMonitors, rules/alerts, Grafana dashboard
scripts/             deploy / verify / rollback / chaos / load / secrets / screenshots
infra/terraform/     bootstrap (state), modules/{network,database,cache,alb,ecs-service,settle}, envs/{staging,prod}
local/               k3d cluster + ingress-nginx values
images/              how 1.9.0 and 1.9.1-rc are produced
docs/                RCA, ADRs, runbook, changes, SLOs, evidence
```
