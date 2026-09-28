| rollout status (readiness) | PASS | ReplicaSet 7b6f6975fb |
| /readyz and /version | PASS | readyz=200 version=1.9.0 expected=1.9.0 |
| GET /settlements x3 | PASS | HTTP 200 200 200  |
| POST /settlements | PASS | HTTP 202 |
| settlement paid end-to-end by worker | FAIL | bank payouts=0 |
| no container restarts (api + worker) | FAIL | settle-api-7b6f6975fb-b7dpd=0 settle-api-7b6f6975fb-wf5db=0 settle-worker-759ffc494b-2zvpj=5 settle-worker-759ffc494b-d6w4h=5  |
| GET /reports/daily | PASS | HTTP 200 7.668306s |
| 5xx ratio, new pods, 2m | PASS | 0.00% (threshold 1%) |
| p99 latency, new pods, excl. reports | PASS | 0.0099s (threshold 1s) |
| no merchant paid twice (bank ledger) | PASS | {"payouts":0,"merchant_dates":0,"paid_more_than_once":[]} |
