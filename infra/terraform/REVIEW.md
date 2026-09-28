# Review of the inherited Terraform draft (`infra/terraform/main.tf`, never applied)

| # | Finding in the draft | Real-world impact if it had been applied | Fix in this repo |
|---|---|---|---|
| 1 | AWS access key + secret key hard-coded in the `provider` block | Anyone with repo read access (and every fork/clone, forever, via git history) gets account credentials. | Removed. Credentials come from the environment (SSO locally, OIDC role in CI). The key must be treated as leaked: deactivate + rotate (RCA action item A7). |
| 2 | Local state, no backend, no locking | State (with DB password) on one laptop; two people applying at once corrupt it; no history. | S3 backend per environment, KMS-encrypted, versioned, TLS-only bucket policy, **S3 native locking** (`use_lockfile = true`) — `bootstrap/`, `envs/*/backend.tf`. |
| 3 | RDS `publicly_accessible = true` + SG `0.0.0.0/0` on **all TCP ports** | The payments database is reachable from the internet; brute-force / CVE exposure of Postgres. | RDS in data subnets with **no internet route**; SG allows 5432 only from the API/worker SGs (`modules/database`). |
| 4 | DB password in plain text in code (`S3ttle-prod-2026`) | Same as #1 for the database; also ends up in state. | `manage_master_user_password = true`: RDS generates and rotates it in Secrets Manager (KMS CMK). ECS injects it at task start. Rotate the leaked one. |
| 5 | No encryption at rest (RDS, Redis), no TLS to Redis, no Redis AUTH | Snapshot/backup exposure; plaintext queue traffic containing payout data. | RDS `storage_encrypted` + CMK; ElastiCache at-rest + in-transit encryption + AUTH token in Secrets Manager; `rds.force_ssl = 1`. |
| 6 | Single subnet, single AZ, `map_public_ip_on_launch = true` | One AZ failure takes settle down; anything launched there gets a public IP. | 2 AZs × 3 tiers (public / app / data), no auto public IPs, NAT per AZ in prod (`modules/network`). |
| 7 | IAM policy `Action "*"` on `Resource "*"` for the app | A compromised container is full account admin. | Task role grants **nothing** (the app calls no AWS APIs); execution role may only pull images, write its log group and read *its two* secrets (`modules/ecs-service`). |
| 8 | `skip_final_snapshot = true`, no backups, no deletion protection | `terraform destroy` or a typo deletes the payments DB with no recovery point. | Final snapshot always; backups 7 d (staging) / 14 d (prod); deletion protection in prod. |
| 9 | Redis `aws_elasticache_cluster`, 1 node, default parameter group | No failover; default `volatile-lru`-style eviction could silently drop queued jobs under memory pressure. | Replication group with Multi-AZ failover in prod; own parameter group with `maxmemory-policy noeviction`. |
| 10 | Oversized instances (`db.m5.large`, `cache.m5.large`) with no environment split | Staging would cost prod money; prod and staging could not differ without copy-paste. | One composition module (`modules/settle`); `envs/staging` and `envs/prod` pass sizes only. Staging ≈ USD 180/month (COST.md). |
| 11 | No provider/Terraform version pins | Unreviewed provider upgrades change behaviour between two applies. | `required_version >= 1.10`, `hashicorp/aws ~> 6.0`, lock file per root. |
| 12 | No compute, no load balancer, no network controls, no logs | The draft could not have run settle at all. | ECS Fargate services for API + worker, ALB (TLS 1.3, HTTP→HTTPS redirect, WAF, access logs), VPC flow logs, KMS-encrypted log groups, ECR with immutable tags + scan on push. |
| 13 | Nothing tied DB capacity to app scaling | The same 600-connections problem as the incident, in AWS. | A Terraform `check` block fails the plan if peak connections (max tasks × deploy surge × workers × pool) exceed `max_connections`. |

## Proof (no apply)

`infra/terraform/check.sh` runs, for `bootstrap/`, `envs/staging/`, `envs/prod/`:
`terraform fmt -check`, `terraform init -backend=false && terraform validate`, `tflint` (AWS
ruleset, recommended preset) and `checkov`. Output: `docs/evidence/terraform-checks.txt`
(local run) and the `terraform` job of every pipeline run.

## Suppressed findings and why

| Check | Where | Justification |
|---|---|---|
| CKV_TF_1 | all roots | Module sources are local paths inside this repository, not remote modules. |
| CKV2_AWS_5 | all roots | False positive: SGs are attached to ECS/RDS/ElastiCache through module outputs, which checkov does not follow. |
| CKV_AWS_144, CKV2_AWS_62, CKV_AWS_18 | state bucket (inline) | No cross-region replica/notifications/access-log bucket for state; versioning + KMS + CloudTrail are sufficient. |
| CKV_AWS_145, CKV_AWS_144, CKV_AWS_18, CKV2_AWS_62 | ALB log bucket (inline) | ALB log delivery only supports SSE-S3; the bucket *is* the access-log bucket. |
| CKV_AWS_260 | ALB port 80 rule (inline) | Port 80 only returns a 301 to HTTPS. |
| CKV2_AWS_57 | Redis AUTH secret (inline) | Rotation needs a coordinated ElastiCache `ROTATE` + task restart; runbook-driven now, automation in NOT-DONE. |
| CKV_AWS_150, CKV_AWS_293 | **staging only** | Deletion protection off so staging can be torn down; no customer data. |
| CKV_AWS_157, CKV2_AWS_50 | **staging only** | Single-AZ RDS and single-node Redis: the biggest cost levers for the USD 250 budget. |
| CKV_AWS_338 | **staging only** | 30-day log retention (prod 365). |
| CKV_AWS_353, CKV_AWS_118 | **staging only** | Performance Insights not available on db.t4g.small; enhanced monitoring not worth it in staging. |
