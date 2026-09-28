| rollout status (readiness) | PASS | ReplicaSet 85b4d8b6b5 |
| /readyz and /version | PASS | readyz=200 version=1.9.1-rc expected=1.9.1-rc |
| GET /settlements x3 | FAIL | HTTP 500 500 500  |
| POST /settlements | PASS | HTTP 202 |
| settlement paid end-to-end by worker | PASS | bank payouts=20 |
| no container restarts (api + worker) | PASS | settle-api-85b4d8b6b5-96rvp=0 settle-api-85b4d8b6b5-cm756=0 settle-worker-6f779f9d85-6q764=0 settle-worker-6f779f9d85-lr85c=0  |
| GET /reports/daily | PASS | HTTP 200 7.788755s |
| 5xx ratio, new pods, 2m | FAIL | 45.60% (threshold 1%) |
| p99 latency, new pods, excl. reports | PASS | 0.00996513918283844s (threshold 1s) |
| no merchant paid twice (bank ledger) | PASS | {"payouts":20,"merchant_dates":20,"paid_more_than_once":[]} |
