import os
from pathlib import Path

import pytest

os.environ.setdefault(
    "DATABASE_URL", os.environ.get("TEST_DATABASE_URL", "postgresql+psycopg://settle:settle@localhost:5432/settle")
)
os.environ.setdefault("REPORT_DELAY_MIN_S", "0")
os.environ.setdefault("REPORT_DELAY_MAX_S", "0.01")
os.environ.setdefault("HEARTBEAT_FILE", "/tmp/test-worker-heartbeat")

MIGRATIONS = Path(__file__).resolve().parents[2] / "migrations"


def _pg_available() -> bool:
    try:
        import psycopg

        from settle import config

        with psycopg.connect(config.DATABASE_URL.replace("+psycopg", ""), connect_timeout=2):
            return True
    except Exception:
        return False


@pytest.fixture
def db():
    if not _pg_available():
        pytest.skip("postgres not available")
    import psycopg

    from settle import config, migrate

    with psycopg.connect(config.DATABASE_URL.replace("+psycopg", ""), autocommit=True) as c:
        c.execute("DROP SCHEMA public CASCADE; CREATE SCHEMA public;")
    migrate.run(MIGRATIONS)
    from settle.db import get_engine

    yield get_engine()
