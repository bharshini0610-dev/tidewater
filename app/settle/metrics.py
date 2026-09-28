"""Prometheus metrics shared by API and worker.

gunicorn runs 4 worker processes per pod, so the API uses prometheus_client's
multiprocess mode (PROMETHEUS_MULTIPROC_DIR on an emptyDir) and /metrics aggregates all
processes. The worker is a single process and serves metrics on its own port.
"""

import os

# prometheus_client switches to multiprocess mode if the variable merely *exists*, even
# when empty (the worker sets it to ""), and then writes .db files into the read-only cwd.
if not os.environ.get("PROMETHEUS_MULTIPROC_DIR"):
    os.environ.pop("PROMETHEUS_MULTIPROC_DIR", None)

from prometheus_client import (  # noqa: E402
    CONTENT_TYPE_LATEST,
    CollectorRegistry,
    Counter,
    Gauge,
    Histogram,
    generate_latest,
    multiprocess,
)

HTTP_REQUESTS = Counter(
    "settle_http_requests_total", "HTTP requests by route template, method and status", ["route", "method", "status"]
)
HTTP_LATENCY = Histogram(
    "settle_http_request_duration_seconds",
    "HTTP request latency by route template and status (status lets the SLO count fast *and* successful)",
    ["route", "method", "status"],
    buckets=(0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 7.5, 10, 15, 30),
)
DB_UNAVAILABLE = Counter("settle_db_unavailable_total", "Requests answered 503 because the DB was slow/unavailable")
DB_POOL_CHECKED_OUT = Gauge(
    "settle_db_pool_checked_out", "DB connections checked out of the pool", multiprocess_mode="livesum"
)

JOBS = Counter("settle_jobs_total", "Settlement jobs by outcome", ["outcome"])
PAYOUTS = Counter("settle_payouts_total", "Payouts confirmed by the bank")
DUPLICATES_PREVENTED = Counter(
    "settle_payout_duplicates_prevented_total",
    "Payout attempts that the idempotency key/unique constraint stopped from paying twice",
)
DUPLICATE_PAYOUTS = Gauge(
    "settle_duplicate_payouts", "Merchant/date pairs with more than one payout row (must always be 0)"
)
QUEUE_DEPTH = Gauge("settle_queue_depth", "Jobs waiting in the settlement queue")
QUEUE_OLDEST_AGE = Gauge("settle_queue_oldest_job_age_seconds", "Age of the oldest waiting or in-flight job")
IN_FLIGHT = Gauge("settle_jobs_in_flight", "Jobs currently being processed by this worker")
JOB_DURATION = Histogram(
    "settle_job_duration_seconds", "Time to process one settlement job", buckets=(0.1, 0.5, 1, 2, 5, 10, 30, 60)
)


def render() -> tuple[bytes, str]:
    if os.environ.get("PROMETHEUS_MULTIPROC_DIR"):
        registry = CollectorRegistry()
        multiprocess.MultiProcessCollector(registry)
        return generate_latest(registry), CONTENT_TYPE_LATEST
    from prometheus_client import REGISTRY

    return generate_latest(REGISTRY), CONTENT_TYPE_LATEST
