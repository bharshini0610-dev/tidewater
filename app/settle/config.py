"""Runtime configuration, all from the environment.

Secrets (DATABASE_URL, REDIS_URL) are never baked into the image or committed; they are
injected by the platform (Kubernetes Secret created by the pipeline locally, AWS Secrets
Manager via ECS task definition in AWS).
"""

import os


def _int(name: str, default: int) -> int:
    return int(os.environ.get(name, default))


def _float(name: str, default: float) -> float:
    return float(os.environ.get(name, default))


APP_VERSION = os.environ.get("APP_VERSION", "dev")
DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql+psycopg://settle:settle@localhost:5432/settle")
REDIS_URL = os.environ.get("REDIS_URL", "redis://localhost:6379/0")
BANK_URL = os.environ.get("BANK_URL", "http://localhost:8080")

# Connection budget (see docs/CHANGES.md "Connection budget"). Per *process*.
DB_POOL_SIZE = _int("DB_POOL_SIZE", 2)
DB_MAX_OVERFLOW = _int("DB_MAX_OVERFLOW", 0)
DB_POOL_TIMEOUT_S = _float("DB_POOL_TIMEOUT_S", 2.0)
DB_STATEMENT_TIMEOUT_MS = _int("DB_STATEMENT_TIMEOUT_MS", 5000)
DB_REPORT_STATEMENT_TIMEOUT_MS = _int("DB_REPORT_STATEMENT_TIMEOUT_MS", 15000)
DB_CONNECT_TIMEOUT_S = _int("DB_CONNECT_TIMEOUT_S", 3)

QUEUE = os.environ.get("QUEUE_NAME", "settle:jobs")
PROCESSING_PREFIX = os.environ.get("PROCESSING_PREFIX", "settle:processing:")
HEARTBEAT_PREFIX = os.environ.get("HEARTBEAT_PREFIX", "settle:heartbeat:")
HEARTBEAT_TTL_S = _int("HEARTBEAT_TTL_S", 30)
BANK_TIMEOUT_S = _float("BANK_TIMEOUT_S", 10.0)
MAX_ATTEMPTS = _int("MAX_ATTEMPTS", 5)
WORKER_METRICS_PORT = _int("WORKER_METRICS_PORT", 9100)
REPORT_DELAY_MIN_S = _float("REPORT_DELAY_MIN_S", 6.0)
REPORT_DELAY_MAX_S = _float("REPORT_DELAY_MAX_S", 9.0)
