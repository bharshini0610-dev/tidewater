| rollout status (readiness) | PASS | ReplicaSet 866bff5cf |
| /readyz and /version | PASS | readyz=200 version=1.9.0 expected=1.9.0 |
| GET /settlements x3 | PASS | HTTP 200 200 200  |
| POST /settlements | PASS | HTTP 202 |
| GET /reports/daily | PASS | HTTP 200 6.909082s |
| 5xx ratio, new pods, 2m | PASS | 0.00% (threshold 1%) |
| p99 latency, new pods, excl. reports | PASS | 0.009951054478394557s (threshold 1s) |
| no merchant paid twice (bank ledger) | PASS | {"payouts":0,"merchant_dates":0,"paid_more_than_once":[]} |
