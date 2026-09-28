"""Forward-only migration runner (run as a Kubernetes Job before each rollout).

* one runner at a time (pg_advisory_lock), idempotent (schema_migrations table)
* only migrations/*.sql; migrations/contract/ requires --include-contract
* `-- migrate:no-transaction` files run in autocommit (CREATE INDEX CONCURRENTLY, batched backfills)
"""

import argparse
import hashlib
import logging
import os
import sys
from pathlib import Path

import psycopg

from settle import config, logging_setup

logging_setup.setup("settle-migrate")
log = logging.getLogger("settle.migrate")
LOCK_ID = 7_202_608_14


def dsn() -> str:
    return config.DATABASE_URL.replace("postgresql+psycopg://", "postgresql://")


def files(root: Path, include_contract: bool) -> list[Path]:
    out = sorted(root.glob("*.sql"))
    if include_contract:
        out += sorted((root / "contract").glob("*.sql"))
    return out


def run(root: Path, include_contract: bool = False, dry_run: bool = False) -> list[str]:
    applied_now: list[str] = []
    with psycopg.connect(dsn(), autocommit=True, connect_timeout=10) as conn:
        conn.execute("SELECT pg_advisory_lock(%s)", (LOCK_ID,))
        try:
            conn.execute(
                "CREATE TABLE IF NOT EXISTS schema_migrations ("
                " version text PRIMARY KEY, checksum text NOT NULL, applied_at timestamptz NOT NULL DEFAULT now())"
            )
            done = {r[0]: r[1] for r in conn.execute("SELECT version, checksum FROM schema_migrations")}
            for f in files(root, include_contract):
                sql = f.read_text()
                checksum = hashlib.sha256(sql.encode()).hexdigest()
                if f.stem in done:
                    if done[f.stem] != checksum:
                        raise SystemExit(f"migration {f.stem} was modified after being applied")
                    continue
                log.info("applying migration", extra={"version": f.stem, "dry_run": dry_run})
                if dry_run:
                    applied_now.append(f.stem)
                    continue
                if sql.lstrip().startswith("-- migrate:no-transaction"):
                    conn.execute(sql)
                    conn.execute(
                        "INSERT INTO schema_migrations (version, checksum) VALUES (%s, %s)", (f.stem, checksum)
                    )
                else:
                    with conn.transaction():
                        conn.execute(sql)
                        conn.execute(
                            "INSERT INTO schema_migrations (version, checksum) VALUES (%s, %s)", (f.stem, checksum)
                        )
                applied_now.append(f.stem)
        finally:
            conn.execute("SELECT pg_advisory_unlock(%s)", (LOCK_ID,))
    log.info("migrations complete", extra={"applied": applied_now})
    return applied_now


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--dir", default=os.environ.get("MIGRATIONS_DIR", "/app/migrations"))
    p.add_argument("--include-contract", action="store_true")
    p.add_argument("--dry-run", action="store_true")
    a = p.parse_args(argv)
    run(Path(a.dir), a.include_contract, a.dry_run)
    return 0


if __name__ == "__main__":
    sys.exit(main())
