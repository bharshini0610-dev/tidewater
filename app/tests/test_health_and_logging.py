import json
import logging
import time

from fastapi.testclient import TestClient


def test_liveness_and_readiness_do_not_touch_the_database(monkeypatch):
    """A slow/dead Postgres must never fail liveness (14 Aug restart storm)."""
    from settle import api

    def boom():
        raise AssertionError("probe touched the database")

    monkeypatch.setattr(api, "get_engine", boom)
    with TestClient(api.app) as c:
        assert c.get("/livez").status_code == 200
        assert c.get("/readyz").status_code == 200
        assert c.get("/healthz").status_code == 200


def test_db_outage_returns_fast_503_not_a_hang(monkeypatch):
    from sqlalchemy import create_engine

    from settle import api

    dead = create_engine(
        "postgresql+psycopg://x:y@127.0.0.1:1/none",
        pool_size=1,
        max_overflow=0,
        pool_timeout=1,
        connect_args={"connect_timeout": 1},
    )
    monkeypatch.setattr(api, "get_engine", lambda: dead)
    with TestClient(api.app) as c:
        t = time.perf_counter()
        r = c.get("/settlements")
        assert r.status_code == 503
        assert r.headers["Retry-After"] == "5"
        assert time.perf_counter() - t < 3


def test_request_id_is_propagated_and_logged_as_json(capsys):
    from settle import api

    with TestClient(api.app) as c:
        r = c.get("/version", headers={"X-Request-ID": "req-abc-123"})
    assert r.headers["X-Request-ID"] == "req-abc-123"
    lines = [json.loads(line) for line in capsys.readouterr().out.splitlines() if line.startswith("{")]
    req = [x for x in lines if x.get("msg") == "request" and x.get("route") == "/version"]
    assert req and req[-1]["request_id"] == "req-abc-123" and req[-1]["status"] == 200


def test_error_logging_is_rate_limited():
    from settle.logging_setup import RateLimitedLogger

    records = []

    class H(logging.Handler):
        def emit(self, record):
            records.append(record)

    lg = logging.getLogger("t-rl")
    lg.addHandler(H())
    rl = RateLimitedLogger(lg, interval=60)
    for _ in range(10_000):
        rl.error("db", "db down")
    assert len(records) == 1


def test_metrics_endpoint_exposes_request_counters():
    from settle import api

    with TestClient(api.app) as c:
        c.get("/version")
        body = c.get("/metrics").text
    assert "settle_http_requests_total" in body
    assert "settle_http_request_duration_seconds_bucket" in body


def test_aws_style_config_builds_urls_without_leaking_into_defaults(monkeypatch):
    import importlib

    from settle import config

    monkeypatch.setenv("DB_HOST", "db.internal")
    monkeypatch.setenv("DB_USER", "settle_admin")
    monkeypatch.setenv("DB_PASSWORD", "p@ss/word")
    monkeypatch.setenv("REDIS_HOST", "redis.internal")
    monkeypatch.setenv("REDIS_AUTH", "tok")
    c = importlib.reload(config)
    assert c.DATABASE_URL == "postgresql+psycopg://settle_admin:p%40ss%2Fword@db.internal:5432/settle?sslmode=require"
    assert c.REDIS_URL == "rediss://:tok@redis.internal:6379/0"
    for k in ("DB_HOST", "DB_USER", "DB_PASSWORD", "REDIS_HOST", "REDIS_AUTH"):
        monkeypatch.delenv(k)
    importlib.reload(config)


def test_empty_multiproc_dir_means_single_process_metrics():
    """Regression: an empty PROMETHEUS_MULTIPROC_DIR crash-looped the worker (read-only fs)."""
    import os
    import subprocess
    import sys

    code = "import settle.worker, prometheus_client.values as v; print(v.ValueClass.__name__)"
    env = {**os.environ, "PROMETHEUS_MULTIPROC_DIR": ""}
    out = subprocess.run([sys.executable, "-c", code], env=env, capture_output=True, text=True, check=True)
    assert out.stdout.strip() == "MutexValue"
