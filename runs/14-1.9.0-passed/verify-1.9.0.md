| rollout status (readiness) | PASS | ReplicaSet 776b4946b7 |
| /readyz and /version | PASS | readyz=200 version=1.9.0 expected=1.9.0 |
| GET /settlements x3 | PASS | HTTP 200 200 200  |
| POST /settlements | PASS | HTTP 202 |
| settlement paid end-to-end by worker | PASS | bank payouts=20 |
| no container restarts (api + worker) | PASS | settle-api-776b4946b7-ncr45=0 settle-api-776b4946b7-sz2hp=0 settle-worker-848c98c76c-4hxvd=0 settle-worker-848c98c76c-wcthq=0  |
| GET /reports/daily | PASS | HTTP 200 8.393272s |
| 5xx ratio, new pods, 2m | PASS | 0.00% (threshold 1%) |
| p99 latency, new pods, excl. reports | PASS | 0.009938979158524526s (threshold 1s) |
| no merchant paid twice (bank ledger) | PASS | {"payouts":20,"merchant_dates":20,"paid_more_than_once":[]} |
