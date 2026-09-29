| rollout status (readiness) | PASS | ReplicaSet 7df77944fc |
| /readyz and /version | PASS | readyz=200 version=1.9.1-rc expected=1.9.1-rc |
| GET /settlements x3 | FAIL | HTTP 500 500 500  |
| POST /settlements | PASS | HTTP 202 |
| settlement paid end-to-end by worker | PASS | bank payouts=20 |
| no container restarts (api + worker) | PASS | settle-api-7df77944fc-59zz9=0 settle-api-7df77944fc-b2fxn=0 settle-worker-57f865d56f-cft78=0 settle-worker-57f865d56f-q762c=0  |
| GET /reports/daily | PASS | HTTP 200 6.443355s |
| 5xx ratio, new pods, 2m | FAIL | 45.68% (threshold 1%) |
| p99 latency, new pods, excl. reports | PASS | 0.020789007338986625s (threshold 1s) |
| no merchant paid twice (bank ledger) | PASS | {"payouts":20,"merchant_dates":20,"paid_more_than_once":[]} |
