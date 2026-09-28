import os

DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql+psycopg://settle:settle@postgres:5432/settle")
REDIS_URL = os.environ.get("REDIS_URL", "redis://redis:6379/0")
BANK_URL = os.environ.get("BANK_URL", "http://mockbank:8080")
QUEUE = "settle:jobs"
