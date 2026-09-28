| rollout status (readiness) | PASS | ReplicaSet 79d849c75f |
| /readyz and /version | PASS | readyz=200 version=1.9.1-rc expected=1.9.1-rc |
| GET /settlements x3 | FAIL | HTTP 500 500 500  |
| POST /settlements | PASS | HTTP 202 |
| settlement paid end-to-end by worker | PASS | bank payouts=20 |
| no container restarts (api + worker) | PASS | settle-api-79d849c75f-7t89w=0 settle-api-79d849c75f-vwm4b=0 settle-worker-7d685555ff-4t26x=0 settle-worker-7d685555ff-868g8=0  |
| GET /reports/daily | PASS | HTTP 200 8.776290s |
| 5xx ratio, new pods, 2m | FAIL | 45.52% (threshold 1%) |
| p99 latency, new pods, excl. reports | PASS | 0.009982850271249495s (threshold 1s) |
| no merchant paid twice (bank ledger) | PASS | {"payouts":20,"merchant_dates":20,"paid_more_than_once":[]} |
