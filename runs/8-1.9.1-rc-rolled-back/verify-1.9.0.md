| rollout status (readiness) | PASS | ReplicaSet cbf476d64 |
| /readyz and /version | FAIL | readyz=200 version=1.9.1-rc expected=1.9.0 |
| GET /settlements x3 | PASS | HTTP 200 200 200  |
| POST /settlements | PASS | HTTP 202 |
| settlement paid end-to-end by worker | PASS | bank payouts=20 |
| no container restarts (api + worker) | PASS | settle-api-cbf476d64-frlt9=0 settle-api-cbf476d64-p9g4l=0 settle-worker-844bc6b7d6-4czkp=0 settle-worker-844bc6b7d6-sn4xf=0  |
| GET /reports/daily | PASS | HTTP 200 8.023379s |
| 5xx ratio, new pods, 2m | PASS | 0.00% (threshold 1%) |
| p99 latency, new pods, excl. reports | PASS | 0.0099s (threshold 1s) |
| no merchant paid twice (bank ledger) | PASS | {"payouts":20,"merchant_dates":20,"paid_more_than_once":[]} |
