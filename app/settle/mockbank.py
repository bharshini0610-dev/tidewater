"""Mock bank API used locally and in CI.

Honours Idempotency-Key exactly like the real bank contract: the same key returns the
original payout (with Idempotent-Replayed: true) instead of creating a second one. It also
keeps a ledger so verification can assert "no merchant was paid twice".
"""

import os
import random
import threading
import time
import uuid

from fastapi import FastAPI, Header, HTTPException, Request

from settle import logging_setup

logging_setup.setup("mockbank")
app = FastAPI(title="mockbank")
_lock = threading.Lock()
_by_key: dict[str, dict] = {}
_paid: dict[str, int] = {}
FAIL_RATE = float(os.environ.get("BANK_FAIL_RATE", "0"))
LATENCY_S = float(os.environ.get("BANK_LATENCY_S", "0.05"))


@app.get("/livez")
def livez():
    return {"status": "alive"}


@app.post("/payouts")
async def payout(request: Request, idempotency_key: str | None = Header(default=None)):
    body = await request.json()
    time.sleep(LATENCY_S)
    if random.random() < FAIL_RATE:
        raise HTTPException(503, "bank temporarily unavailable")
    with _lock:
        if idempotency_key and idempotency_key in _by_key:
            from fastapi.responses import JSONResponse

            return JSONResponse(_by_key[idempotency_key], headers={"Idempotent-Replayed": "true"})
        res = {"payout_id": uuid.uuid4().hex, **body}
        if idempotency_key:
            _by_key[idempotency_key] = res
        k = f"{body['merchant_id']}:{body['settlement_date']}"
        _paid[k] = _paid.get(k, 0) + 1
    return res


@app.get("/stats")
def stats():
    with _lock:
        return {
            "payouts": sum(_paid.values()),
            "merchant_dates": len(_paid),
            "paid_more_than_once": sorted(k for k, v in _paid.items() if v > 1),
        }
