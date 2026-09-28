import json
import logging
import time

import httpx
import redis
from sqlalchemy import text

from settle import config
from settle.db import engine

logging.basicConfig(filename="/var/log/settle/worker.log", level=logging.DEBUG)
log = logging.getLogger("settle-worker")
r = redis.Redis.from_url(config.REDIS_URL)


def process(job):
    with engine.begin() as c:
        amount = c.execute(
            text("SELECT coalesce(sum(amount_cents),0) FROM settlements WHERE merchant_id=:m AND settlement_date=:d"),
            {"m": job["merchant_id"], "d": job["settlement_date"]},
        ).scalar()
    httpx.post(f"{config.BANK_URL}/payouts", json={**job, "amount_cents": int(amount)}, timeout=30)
    with engine.begin() as c:
        c.execute(
            text("INSERT INTO payouts (merchant_id, settlement_date, amount_cents) VALUES (:m, :d, :a)"),
            {"m": job["merchant_id"], "d": job["settlement_date"], "a": int(amount)},
        )


def main():
    while True:
        try:
            _, raw = r.brpop(config.QUEUE)
            job = json.loads(raw)
            try:
                process(job)
            except Exception:
                log.exception("job failed, retrying")
                r.lpush(config.QUEUE, raw)
        except Exception:
            log.exception("worker loop error")
            continue


if __name__ == "__main__":
    main()
