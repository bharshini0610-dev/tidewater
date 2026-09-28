| rollout status (readiness) | PASS | ReplicaSet 79d849c75f |
| /readyz and /version | PASS | readyz=200 version=1.9.1-rc expected=1.9.1-rc |
| GET /settlements x3 | FAIL | HTTP 500 500 500  |
| POST /settlements | PASS | HTTP 202 |
| settlement paid end-to-end by worker | PASS | bank payouts=20 |
| no container restarts (api + worker) | PASS | settle-api-79d849c75f-w5pc7=0 settle-api-79d849c75f-xgrsv=0 settle-worker-7d685555ff-fn9nr=0 settle-worker-7d685555ff-v5phd=0  |
| GET /reports/daily | PASS | HTTP 200 8.369650s |
| 5xx ratio, new pods, 2m | FAIL | 47.01% (threshold 1%) |
| p99 latency, new pods, excl. reports | PASS | 0.009967583367719714s (threshold 1s) |
| no merchant paid twice (bank ledger) | PASS | {"payouts":20,"merchant_dates":20,"paid_more_than_once":[]} |
