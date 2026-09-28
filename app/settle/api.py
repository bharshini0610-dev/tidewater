import json
import logging
import random
import threading
import time
import uuid
from contextlib import asynccontextmanager
from datetime import date, datetime, timezone

import redis
from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.responses import JSONResponse
from sqlalchemy import text
from sqlalchemy.exc import OperationalError
from sqlalchemy.exc import TimeoutError as PoolTimeout

from settle import config, logging_setup, metrics
from settle.db import get_engine, pool_checked_out

logging_setup.setup("settle-api")
log = logging.getLogger("settle.api")
dep_log = logging_setup.RateLimitedLogger(log)

_redis = None
_started = False
# At most one report per process holds a DB connection, so OLTP requests always have one.
_report_slot = threading.BoundedSemaphore(1)


def get_redis() -> redis.Redis:
    global _redis
    if _redis is None:
        _redis = redis.Redis.from_url(config.REDIS_URL, socket_timeout=2, socket_connect_timeout=2)
    return _redis


@asynccontextmanager
async def lifespan(_app: FastAPI):
    global _started
    _started = True
    log.info("started", extra={"version": config.APP_VERSION})
    yield
    log.info("shutting down", extra={"version": config.APP_VERSION})


app = FastAPI(title="settle-api", version=config.APP_VERSION, lifespan=lifespan)


@app.middleware("http")
async def request_context(request: Request, call_next):
    rid = request.headers.get("x-request-id") or uuid.uuid4().hex
    token = logging_setup.request_id_var.set(rid)
    start = time.perf_counter()
    status = 500
    try:
        response = await call_next(request)
        status = response.status_code
        response.headers["X-Request-ID"] = rid
        return response
    finally:
        route = request.scope.get("route")
        route_tpl = getattr(route, "path", "unmatched")
        elapsed = time.perf_counter() - start
        if route_tpl not in ("/metrics", "/livez", "/readyz"):
            metrics.HTTP_REQUESTS.labels(route_tpl, request.method, str(status)).inc()
            metrics.HTTP_LATENCY.labels(route_tpl, request.method).observe(elapsed)
            log.info(
                "request",
                extra={
                    "method": request.method,
                    "route": route_tpl,
                    "status": status,
                    "duration_ms": round(elapsed * 1000, 1),
                },
            )
        metrics.DB_POOL_CHECKED_OUT.set(pool_checked_out())
        logging_setup.request_id_var.reset(token)


@app.exception_handler(OperationalError)
@app.exception_handler(PoolTimeout)
async def db_unavailable(_request: Request, exc: Exception):
    # Fail fast with a retryable status instead of holding the request (and nginx) open.
    metrics.DB_UNAVAILABLE.inc()
    dep_log.error("db", "database unavailable or slow", error=type(exc).__name__)
    return JSONResponse({"detail": "database unavailable"}, status_code=503, headers={"Retry-After": "5"})


# --- health -----------------------------------------------------------------------------
# Liveness answers only "is this process able to serve HTTP at all". It never touches
# Postgres/Redis: a slow shared dependency must not make the kubelet kill every pod at
# once (that is what turned a slow database into a restart storm on 14 Aug).
@app.get("/livez")
def livez():
    return {"status": "alive"}


# Readiness answers "has this process finished starting". Dependency health is exposed on
# /healthz/deps for dashboards/alerts, not probes; see docs/DECISIONS.md ADR-004.
@app.get("/readyz")
def readyz(response: Response):
    if not _started:
        response.status_code = 503
        return {"status": "starting"}
    return {"status": "ready", "version": config.APP_VERSION}


@app.get("/healthz")
def healthz():
    """Kept for backwards compatibility with old monitors; same semantics as /livez."""
    return {"status": "alive"}


@app.get("/healthz/deps")
def healthz_deps(response: Response):
    out = {}
    try:
        with get_engine().connect() as c:
            c.execute(text("SELECT 1"))
        out["postgres"] = "ok"
    except Exception as e:  # noqa: BLE001
        out["postgres"] = f"error: {type(e).__name__}"
    try:
        get_redis().ping()
        out["redis"] = "ok"
    except Exception as e:  # noqa: BLE001
        out["redis"] = f"error: {type(e).__name__}"
    if any(v != "ok" for v in out.values()):
        response.status_code = 503
    return out


@app.get("/version")
def version():
    return {"version": config.APP_VERSION}


@app.get("/metrics")
def prom_metrics():
    body, ctype = metrics.render()
    return Response(body, media_type=ctype)


# --- business endpoints (logic unchanged; only operability wrappers added) ---------------
@app.get("/settlements")
def list_settlements(limit: int = 50):
    limit = max(1, min(limit, 500))
    with get_engine().connect() as c:
        rows = (
            c.execute(
                text(
                    "SELECT id, merchant_id, settlement_date, "
                    "COALESCE(amount_cents, (amount * 100)::bigint) AS amount_cents, status "
                    "FROM settlements ORDER BY id DESC LIMIT :l"
                ),
                {"l": limit},
            )
            .mappings()
            .all()
        )
    return [dict(x) for x in rows]


@app.post("/settlements", status_code=202)
def create_settlement(merchant_id: int, settlement_date: date | None = None):
    d = (settlement_date or date.today()).isoformat()
    job = {
        "job_id": uuid.uuid4().hex,
        "merchant_id": merchant_id,
        "settlement_date": d,
        "request_id": logging_setup.request_id_var.get(),
        "enqueued_at": datetime.now(timezone.utc).timestamp(),
        "attempts": 0,
    }
    try:
        get_redis().lpush(config.QUEUE, json.dumps(job))
    except redis.RedisError as e:
        dep_log.error("redis", "redis unavailable", error=type(e).__name__)
        raise HTTPException(503, "queue unavailable", headers={"Retry-After": "5"}) from e
    log.info("settlement enqueued", extra={"job_id": job["job_id"], "merchant_id": merchant_id, "settlement_date": d})
    return {"queued": True, "job_id": job["job_id"]}


@app.get("/reports/daily")
def daily_report():
    if not _report_slot.acquire(timeout=2):
        raise HTTPException(429, "report already running in this worker, retry shortly", headers={"Retry-After": "5"})
    try:
        delay = random.uniform(config.REPORT_DELAY_MIN_S, config.REPORT_DELAY_MAX_S)
        with get_engine().connect() as c:
            c.execute(text(f"SET LOCAL statement_timeout = {int(config.DB_REPORT_STATEMENT_TIMEOUT_MS)}"))
            # The production report is a heavy aggregate (~6-9 s); pg_sleep reproduces its cost locally.
            c.execute(text("SELECT pg_sleep(:d)"), {"d": delay})
            rows = c.execute(
                text(
                    "SELECT settlement_date, sum(COALESCE(amount_cents, (amount * 100)::bigint)) "
                    "FROM settlements GROUP BY 1 ORDER BY 1 DESC LIMIT 31"
                )
            ).all()
            c.rollback()
        return [{"date": str(a), "total_cents": int(b or 0)} for a, b in rows]
    finally:
        _report_slot.release()
