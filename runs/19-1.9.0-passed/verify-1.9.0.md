| rollout status (readiness) | PASS | ReplicaSet df98874c |
| /readyz and /version | PASS | readyz=200 version=1.9.0 expected=1.9.0 |
| GET /settlements x3 | PASS | HTTP 200 200 200  |
| POST /settlements | PASS | HTTP 202 |
| settlement paid end-to-end by worker | PASS | bank payouts=20 |
| no container restarts (api + worker) | PASS | settle-api-df98874c-69pc9=0 settle-api-df98874c-jxctg=0 settle-worker-9cddc8655-j879p=0 settle-worker-9cddc8655-tznps=0  |
| GET /reports/daily | PASS | HTTP 200 7.674043s |
| 5xx ratio, new pods, 2m | PASS | 0.00% (threshold 1%) |
| p99 latency, new pods, excl. reports | PASS | 0.009918105336429919s (threshold 1s) |
| no merchant paid twice (bank ledger) | PASS | {"payouts":20,"merchant_dates":20,"paid_more_than_once":[]} |
