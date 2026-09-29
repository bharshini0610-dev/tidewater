| rollout status (readiness) | PASS | ReplicaSet 776f88dd49 |
| /readyz and /version | PASS | readyz=200 version=1.9.1-rc expected=1.9.1-rc |
| GET /settlements x3 | FAIL | HTTP 500 500 500  |
| POST /settlements | PASS | HTTP 202 |
| settlement paid end-to-end by worker | PASS | bank payouts=20 |
| no container restarts (api + worker) | PASS | settle-api-776f88dd49-l6dht=0 settle-api-776f88dd49-t7lx8=0 settle-worker-7c89479dd5-gzvxn=0 settle-worker-7c89479dd5-s6p82=0  |
| GET /reports/daily | PASS | HTTP 200 7.775062s |
| 5xx ratio, new pods, 2m | FAIL | 45.59% (threshold 1%) |
| p99 latency, new pods, excl. reports | PASS | 0.009977108795592575s (threshold 1s) |
| no merchant paid twice (bank ledger) | PASS | {"payouts":20,"merchant_dates":20,"paid_more_than_once":[]} |
