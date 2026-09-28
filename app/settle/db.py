"""Database engine with a bounded pool.

Inherited: pool_size=5, max_overflow=10 per gunicorn worker -> 15 connections per process,
60 per pod, 600 at HPA max 10 against max_connections=100. Now the pool is small, has no
overflow, waits at most DB_POOL_TIMEOUT_S for a connection (fail fast -> 503 instead of
piling up), and every statement has a server-side timeout.
"""

from sqlalchemy import create_engine, event
from sqlalchemy.engine import Engine

from settle import config

_engine: Engine | None = None


def get_engine() -> Engine:
    global _engine
    if _engine is None:
        _engine = create_engine(
            config.DATABASE_URL,
            pool_size=config.DB_POOL_SIZE,
            max_overflow=config.DB_MAX_OVERFLOW,
            pool_timeout=config.DB_POOL_TIMEOUT_S,
            pool_pre_ping=True,
            pool_recycle=1800,
            connect_args={
                "connect_timeout": config.DB_CONNECT_TIMEOUT_S,
                "application_name": f"settle-{config.APP_VERSION}",
            },
        )

        @event.listens_for(_engine, "connect")
        def _set_timeouts(dbapi_conn, _record):  # pragma: no cover - needs a real DB
            with dbapi_conn.cursor() as cur:
                cur.execute(f"SET statement_timeout = {int(config.DB_STATEMENT_TIMEOUT_MS)}")
                cur.execute("SET idle_in_transaction_session_timeout = 10000")
            dbapi_conn.commit()

    return _engine


def pool_checked_out() -> int:
    return _engine.pool.checkedout() if _engine is not None else 0
