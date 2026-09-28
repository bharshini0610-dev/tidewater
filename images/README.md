# Release images

The brief ships two pre-built images: `settle-api:1.9.0` (good) and `settle-api:1.9.1-rc`
(untrusted release candidate). Those images were not supplied, so both are **built by the
pipeline from this repository**:

| Release | How it is built | Expected pipeline result |
|---|---|---|
| `1.9.0` | `app/` as-is | deploys, passes verification, becomes the production pointer (`deploy/releases/production.json`) |
| `1.9.1-rc` | `app/` + `settle-api-1.9.1-rc/regression.patch` | builds and scans clean, pods start and pass readiness (the rollout itself is "green"), **post-deploy verification fails** → automatic rollback to 1.9.0 |

The regression is realistic for this codebase: the RC's `GET /settlements` reads a column
(`amount_minor`) that no migration has created — the same class of code/schema mismatch
as the original 0008 incident. Readiness does not query the DB (by design, ADR-004), so
only behavioural verification can catch it — which is exactly what the pipeline must prove.
