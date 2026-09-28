# Staging cost estimate (must be < USD 250/month)

Region eu-west-1, on-demand list prices, 730 h/month. **Rough estimate from published list
prices — re-check in the AWS Pricing Calculator before committing to it; prices change.**

| Item | Staging sizing | Approx. USD/month |
|---|---|---|
| ECS Fargate — settle-api | 2 tasks × 0.5 vCPU / 1 GB (x86) | 36 |
| ECS Fargate — settle-worker | 1 task × 0.25 vCPU / 0.5 GB | 9 |
| Application Load Balancer | 1 ALB + low LCU usage | 24 |
| NAT Gateway | **1** (not one per AZ) + ~50 GB processed | 38 |
| Public IPv4 addresses | NAT EIP + 2 ALB IPs | 11 |
| RDS PostgreSQL 15 | db.t4g.small, **single-AZ**, 20 GB gp3, 7-day backups | 29 |
| ElastiCache Redis 7 | cache.t4g.micro, **1 node** | 13 |
| WAF | 1 web ACL + 5 rules + low request volume | 11 |
| CloudWatch | logs (30-day retention), Container Insights, alarms | 15 |
| KMS, Secrets Manager (2), ECR, S3 | | 5 |
| **Total** | | **≈ 190** |

## Trade-offs made to hit the budget (prod does the opposite)

| Lever | Saving | Risk accepted in staging |
|---|---|---|
| One NAT gateway instead of two | ~35 | An outage of that AZ cuts egress (bank sandbox, ECR) for both AZs. |
| No interface VPC endpoints (ECR, Secrets Manager, Logs) | ~64 | Image pulls and log traffic go through NAT (paid per GB) instead. |
| Single-AZ RDS | ~29 | AZ failure = DB down until restored; fine for staging. |
| Redis without replica | ~13 | No automatic failover; jobs are in AOF-less memory — re-enqueue from DB if lost. |
| t4g burstable instances | ~120 vs m7g | CPU credits can run out under a load test — watch `CPUCreditBalance`. |
| 30-day log retention | ~5 | Less history for investigations. |

Further options if the budget tightens: scale ECS services to 0 outside office hours
(scheduled scaling, ~-30), Fargate Spot for the worker (~-6), or drop Container Insights (~-5).
