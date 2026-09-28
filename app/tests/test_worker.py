import json
import threading

import fakeredis
import httpx
import pytest
from sqlalchemy import text


class FakeBank:
    """Honours Idempotency-Key like the real bank; counts real payments."""

    def __init__(self):
        self.by_key = {}
        self.paid = {}
        self.fail_next = False

    def handler(self, request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        key = request.headers.get("Idempotency-Key")
        if key in self.by_key:
            return httpx.Response(200, json=self.by_key[key], headers={"Idempotent-Replayed": "true"})
        res = {"payout_id": f"p{len(self.by_key) + 1}", **body}
        self.by_key[key] = res
        k = f"{body['merchant_id']}:{body['settlement_date']}"
        self.paid[k] = self.paid.get(k, 0) + 1
        return httpx.Response(200, json=res)


def make_worker(db, bank):
    from settle.worker import Worker

    r = fakeredis.FakeRedis()
    client = httpx.Client(base_url="http://bank", transport=httpx.MockTransport(bank.handler))
    return Worker(r, engine=db, bank=client), r


def seed(db, merchant=1, day="2026-08-14", cents=12345):
    with db.begin() as c:
        c.execute(text("INSERT INTO merchants (id, name) VALUES (:m, 'm') ON CONFLICT DO NOTHING"), {"m": merchant})
        c.execute(
            text("INSERT INTO settlements (merchant_id, settlement_date, amount) VALUES (:m, :d, :a)"),
            {"m": merchant, "d": day, "a": cents / 100},
        )


def job(merchant=1, day="2026-08-14"):
    return json.dumps(
        {
            "job_id": "j1",
            "merchant_id": merchant,
            "settlement_date": day,
            "request_id": "r1",
            "enqueued_at": 0,
            "attempts": 0,
        }
    )


def test_same_job_delivered_twice_pays_once(db):
    bank = FakeBank()
    w, r = make_worker(db, bank)
    seed(db)
    r.lpush("settle:jobs", job(), job())  # e.g. retried POST, or re-queued after a crash
    w.handle(w.fetch(0))
    w.handle(w.fetch(0))
    assert bank.paid == {"1:2026-08-14": 1}
    with db.connect() as c:
        assert c.execute(text("SELECT count(*) FROM payouts")).scalar() == 1


def test_crash_after_bank_paid_before_db_update_does_not_pay_twice(db, monkeypatch):
    """The exact 14 Aug window: bank call succeeded, pod died before recording it."""
    bank = FakeBank()
    w, r = make_worker(db, bank)
    seed(db)
    r.lpush("settle:jobs", job())
    raw = w.fetch(0)

    real_begin = db.begin
    calls = {"n": 0}

    def begin_then_die():
        calls["n"] += 1
        if calls["n"] == 2:  # the UPDATE ... status='sent' transaction
            raise RuntimeError("SIGKILL")
        return real_begin()

    monkeypatch.setattr(db, "begin", begin_then_die)
    with pytest.raises(RuntimeError):
        w.process(json.loads(raw))
    monkeypatch.setattr(db, "begin", real_begin)
    # The job is still in the processing list (never acked) -> the reaper puts it back.
    assert r.llen(w_processing(w)) == 1
    assert w.reap_orphans() == 1
    w.handle(w.fetch(0))
    assert bank.paid == {"1:2026-08-14": 1}
    with db.connect() as c:
        assert c.execute(text("SELECT status FROM payouts")).scalar() == "sent"


def w_processing(w):
    from settle import worker

    return worker.PROCESSING


def test_failed_job_is_retried_then_dead_lettered(db):
    from settle import config

    def bank_down(_request):
        return httpx.Response(503)

    from settle.worker import Worker

    r = fakeredis.FakeRedis()
    w = Worker(r, engine=db, bank=httpx.Client(base_url="http://bank", transport=httpx.MockTransport(bank_down)))
    seed(db)
    r.lpush("settle:jobs", job())
    for _ in range(config.MAX_ATTEMPTS):
        w.handle(w.fetch(0))
    assert r.llen("settle:jobs") == 0
    assert r.llen("settle:jobs:dead") == 1
    assert r.llen(w_processing(w)) == 0


def test_sigterm_finishes_in_flight_job_then_exits(db):
    from settle import worker

    bank = FakeBank()
    w, r = make_worker(db, bank)
    seed(db)
    r.lpush("settle:jobs", job())
    worker._stop.clear()
    orig = w.process

    def process_and_signal(j):
        worker._handle_sigterm(15, None)  # SIGTERM arrives mid-job
        return orig(j)

    w.process = process_and_signal
    t = threading.Thread(target=w.run)
    t.start()
    t.join(timeout=10)
    assert not t.is_alive()
    assert bank.paid == {"1:2026-08-14": 1}
    assert r.llen(w_processing(w)) == 0  # acked, not lost
    worker._stop.clear()
