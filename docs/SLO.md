# SLOs and alerts for settle

## SLO-1 — API availability and latency
**99.5% of API requests (excluding `/reports/daily`) succeed (non-5xx) *and* complete in under
500 ms, measured over 28 days.**
* SLI: `settle:slo_good:rate5m / settle:slo_requests:rate5m`, from
  `settle_http_request_duration_seconds_bucket{le="0.5", status!~"5.."}`.
* Budget: 0.5% ≈ 3 h 22 min of total failure per 28 days.
* `/reports/daily` is a batch-style endpoint (6–9 s by design) with its own 15 s statement timeout. It is tracked on
  the dashboard, not in this SLO.

## SLO-2 — Settlement correctness and freshness
**Correctness: 100% of merchant/date settlements are paid at most once. Freshness: 99% of settlement jobs are
paid within 15 minutes of being enqueued.**
* Correctness SLI: `settle_duplicate_payouts` (merchant/date pairs with more than one payout row in the last 24 h),
  computed by the worker from the database. Target 0, always.
* Freshness SLI: `settle_queue_oldest_job_age_seconds` (oldest queued *or* in-flight job).

## Alerts (5 — all page, all actionable, all link to RUNBOOK.md)

| Alert | Expression (simplified) | For | Protects |
|---|---|---|---|
| SettleApiErrorBudgetBurn | error ratio 5m > 7.2% **and** 1h > 7.2% (14.4× burn) | 2m | SLO-1 |
| SettlePodsRestarting | `increase(kube_pod_container_status_restarts_total{namespace="settle"}[10m]) > 2` | 1m | cause of SLO-1 burn |
| SettlePostgresConnectionsHigh | `sum(pg_stat_activity_count) / max(pg_settings_max_connections) > 0.8` | 2m | leading indicator |
| SettleDuplicatePayout | `max(settle_duplicate_payouts) > 0` | 0 | SLO-2 correctness |
| SettleSettlementsStale | oldest job age > 900 s, or no worker `up` | 5m | SLO-2 freshness |

## E4 — Would these alerts have fired on 14 Aug, and how much earlier?

> The Grafana CSV exports from the evidence bundle were not supplied. The table below uses
> only the timestamps in the brief (deploy 14:02, errors 14:05–14:51, restart loop, DiskPressure,
> detection by finance "later") and the alert definitions above. `scripts/replay_alerts.py` computes the
> exact minute for each alert from the CSVs once they are available.

| Alert | Condition becomes true | + `for` + ~30 s scrape/eval | Est. first page | Actual detection | Earlier by |
|---|---|---|---|---|---|
| SettlePostgresConnectionsHigh | connections > 80 once queries block on the 0008 lock (~14:03) | 2 m | **≈ 14:05–14:06** | finance, after the incident | ≥ 45 min before the outage ended; hours–days before finance |
| SettlePodsRestarting | 3rd restart of a pod within 10 min. Liveness `periodSeconds 5 × failureThreshold 1` + restart back-off → ~14:05–14:07 | 1 m | **≈ 14:07–14:08** | as above | ≈ 43 min before recovery |
| SettleApiErrorBudgetBurn | 5m ratio > 7.2% reached within ~1 min of the 14:05 errors; the 1h window follows because traffic before 14:02 was low-error | 2 m | **≈ 14:08** | as above | ≈ 43 min before recovery |
| SettleDuplicatePayout | first merchant/date with 2 payout rows (first retry after a failed INSERT, 14:05–14:51) | 0 | **within ~30 s of the first duplicate** | finance reconciliation | the whole finance delay; most of the 37 prevented if workers had been stopped at the first page |
| SettleSettlementsStale | only if jobs waited > 15 min (workers restarting/evicted) | 5 m | ≈ 14:25 (if queue stalled) | — | — |

**Headline:** the first page would have gone out around **14:05–14:08**, 3–6 minutes after the
deploy, instead of at finance reconciliation. The duplicate-payout page would have given a clear
instruction (stop the worker) that limits the damage to the first few merchants.
