import json
import logging
import random
import time
from datetime import date

import redis
from fastapi import FastAPI
from sqlalchemy import text

from settle import config
from settle.db import engine

logging.basicConfig(filename="/var/log/settle/api.log", level=logging.DEBUG)
log = logging.getLogger("settle-api")

app = FastAPI()
r = redis.Redis.from_url(config.REDIS_URL)


@app.get("/healthz")
def healthz():
    with engine.connect() as c:
        c.execute(text("SELECT count(*) FROM settlements"))
    return {"ok": True}


@app.get("/settlements")
def list_settlements(limit: int = 50):
    with engine.connect() as c:
        rows = c.execute(
            text("SELECT id, merchant_id, settlement_date, amount_cents, status FROM settlements ORDER BY id DESC LIMIT :l"),
            {"l": limit},
        ).mappings().all()
    return [dict(x) for x in rows]


@app.post("/settlements", status_code=202)
def create_settlement(merchant_id: int, settlement_date: date | None = None):
    d = (settlement_date or date.today()).isoformat()
    r.lpush(config.QUEUE, json.dumps({"merchant_id": merchant_id, "settlement_date": d}))
    log.debug("enqueued %s %s", merchant_id, d)
    return {"queued": True}


@app.get("/reports/daily")
def daily_report():
    time.sleep(random.uniform(6, 9))
    with engine.connect() as c:
        rows = c.execute(text("SELECT settlement_date, sum(amount_cents) FROM settlements GROUP BY 1")).all()
    return [{"date": str(a), "total_cents": int(b or 0)} for a, b in rows]
