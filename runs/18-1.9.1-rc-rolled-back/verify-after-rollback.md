| rollout status (readiness) | PASS | ReplicaSet 5487b49847 |
| /readyz and /version | PASS | readyz=200 version=1.9.0 expected=1.9.0 |
| GET /settlements x3 | PASS | HTTP 200 200 200  |
| POST /settlements | PASS | HTTP 202 |
| settlement paid end-to-end by worker | PASS | bank payouts=20 |
| no container restarts (api + worker) | PASS | settle-api-5487b49847-rqwdg=0 settle-api-5487b49847-vcj6r=0 settle-worker-56c79569d7-8g9f6=0 settle-worker-56c79569d7-p67n4=0  |
| GET /reports/daily | PASS | HTTP 200 8.472668s |
| 5xx ratio, new pods, 2m | PASS | 0.00% (threshold 1%) |
| p99 latency, new pods, excl. reports | PASS | 0.009899999999999999s (threshold 1s) |
| no merchant paid twice (bank ledger) | PASS | {"payouts":20,"merchant_dates":20,"paid_more_than_once":[]} |
