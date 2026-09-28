| rollout status (readiness) | PASS | ReplicaSet c76994497 |
| /readyz and /version | PASS | readyz=200 version=1.9.0 expected=1.9.0 |
| GET /settlements x3 | PASS | HTTP 200 200 200  |
| POST /settlements | PASS | HTTP 202 |
| settlement paid end-to-end by worker | PASS | bank payouts=20 |
| no container restarts (api + worker) | PASS | settle-api-c76994497-4ch9c=0 settle-api-c76994497-lktfj=0 settle-worker-7bb6d87577-6pj46=0 settle-worker-7bb6d87577-pw8ft=0  |
| GET /reports/daily | PASS | HTTP 200 7.795328s |
| 5xx ratio, new pods, 2m | PASS | 0.00% (threshold 1%) |
| p99 latency, new pods, excl. reports | PASS | 0.13590764199858513s (threshold 1s) |
| no merchant paid twice (bank ledger) | PASS | {"payouts":20,"merchant_dates":20,"paid_more_than_once":[]} |
