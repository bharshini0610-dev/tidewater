"""Settlement worker: pays each merchant exactly once per settlement date.

What changed and why (14 Aug: 37 merchants paid twice):
* Reliable queue. Jobs are atomically moved (BLMOVE) from the queue to a per-worker
  processing list and removed only after the payout is recorded. A killed worker no longer
  loses the job, and a reaper re-queues jobs of workers whose heartbeat expired.
* Graceful shutdown. SIGTERM stops taking new jobs, the in-flight job finishes, then the
  process exits (terminationGracePeriodSeconds is sized above the worst-case job time).
* Idempotency. Before calling the bank the worker claims the payout row
  (UNIQUE idempotency_key = merchant_id:settlement_date). The bank call carries the same
  Idempotency-Key, so a retry after a crash *between* "bank paid" and "row marked sent"
  is answered by the bank with the original payout instead of paying again.
* Bounded retries with backoff, dead-letter queue, rate-limited error logging.
"""

import json
import logging
import os
import random
import signal
import socket
import threading
import time
from pathlib import Path

import httpx
import redis
from prometheus_client import start_http_server
from sqlalchemy import text

from settle import config, logging_setup, metrics
from settle.db import get_engine

logging_setup.setup("settle-worker")
log = logging.getLogger("settle.worker")
dep_log = logging_setup.RateLimitedLogger(log)

WORKER_ID = os.environ.get("HOSTNAME", socket.gethostname())
PROCESSING = f"{config.PROCESSING_PREFIX}{WORKER_ID}"
HEARTBEAT = f"{config.HEARTBEAT_PREFIX}{WORKER_ID}"
DEAD_LETTER = f"{config.QUEUE}:dead"
HEARTBEAT_FILE = Path(os.environ.get("HEARTBEAT_FILE", "/tmp/worker-heartbeat"))  # noqa: S108 - emptyDir, liveness only

_stop = threading.Event()


def idempotency_key(job: dict) -> str:
    return f"{int(job['merchant_id'])}:{job['settlement_date']}"


def _handle_sigterm(signum, _frame):
    log.info("signal received, draining", extra={"signal": signum})
    _stop.set()


class Worker:
    def __init__(self, r: redis.Redis, engine=None, bank: httpx.Client | None = None):
        self.r = r
        self._engine = engine
        self.bank = bank or httpx.Client(base_url=config.BANK_URL, timeout=config.BANK_TIMEOUT_S)

    @property
    def engine(self):
        return self._engine or get_engine()

    # -- queue mechanics ------------------------------------------------------------------
    def heartbeat(self) -> None:
        HEARTBEAT_FILE.touch()
        try:
            self.r.set(HEARTBEAT, int(time.time()), ex=config.HEARTBEAT_TTL_S)
        except redis.RedisError:
            pass

    def reap_orphans(self) -> int:
        """Return jobs held by workers that died without draining back to the queue."""
        moved = 0
        for key in self.r.scan_iter(f"{config.PROCESSING_PREFIX}*"):
            key = key.decode() if isinstance(key, bytes) else key
            owner = key[len(config.PROCESSING_PREFIX) :]
            if owner != WORKER_ID and self.r.exists(f"{config.HEARTBEAT_PREFIX}{owner}"):
                continue
            while self.r.lmove(key, config.QUEUE, "RIGHT", "RIGHT") is not None:
                moved += 1
        if moved:
            log.warning("re-queued orphaned jobs", extra={"count": moved})
        return moved

    def fetch(self, timeout: int = 2) -> bytes | None:
        # Oldest job is at the right; it moves atomically into our processing list.
        return self.r.blmove(config.QUEUE, PROCESSING, timeout, "RIGHT", "LEFT")

    def ack(self, raw: bytes) -> None:
        self.r.lrem(PROCESSING, 1, raw)

    def retry_or_dead_letter(self, raw: bytes, job: dict, err: str) -> None:
        job["attempts"] = int(job.get("attempts", 0)) + 1
        job["last_error"] = err
        target = config.QUEUE if job["attempts"] < config.MAX_ATTEMPTS else DEAD_LETTER
        pipe = self.r.pipeline()
        pipe.lpush(target, json.dumps(job))
        pipe.lrem(PROCESSING, 1, raw)
        pipe.execute()
        metrics.JOBS.labels("retried" if target == config.QUEUE else "dead_lettered").inc()

    # -- the settlement itself (business logic unchanged: amount = sum of settlements) -----
    def process(self, job: dict) -> str:
        key = idempotency_key(job)
        with self.engine.begin() as c:
            amount = c.execute(
                text(
                    "SELECT COALESCE(sum(COALESCE(amount_cents, (amount * 100)::bigint)), 0) "
                    "FROM settlements WHERE merchant_id = :m AND settlement_date = :d"
                ),
                {"m": job["merchant_id"], "d": job["settlement_date"]},
            ).scalar()
            # Claim the payout. The UNIQUE index on idempotency_key makes this the single
            # point where "pay this merchant for this date" can happen at most once.
            row = c.execute(
                text(
                    "INSERT INTO payouts (merchant_id, settlement_date, amount, amount_cents, idempotency_key, status) "
                    "VALUES (:m, :d, :a / 100.0, :a, :k, 'pending') "
                    "ON CONFLICT (idempotency_key) WHERE idempotency_key IS NOT NULL DO NOTHING RETURNING id"
                ),
                {"m": job["merchant_id"], "d": job["settlement_date"], "a": int(amount), "k": key},
            ).first()
            if row is None:
                status = c.execute(text("SELECT status FROM payouts WHERE idempotency_key = :k"), {"k": key}).scalar()
                if status == "sent":
                    metrics.DUPLICATES_PREVENTED.inc()
                    log.warning("payout already sent, not paying again", extra={"idempotency_key": key})
                    return "duplicate_prevented"
                amount = c.execute(
                    text("SELECT amount_cents FROM payouts WHERE idempotency_key = :k"), {"k": key}
                ).scalar()

        resp = self.bank.post(
            "/payouts",
            json={
                "merchant_id": job["merchant_id"],
                "settlement_date": job["settlement_date"],
                "amount_cents": int(amount),
            },
            headers={"Idempotency-Key": key, "X-Request-ID": job.get("request_id") or ""},
        )
        resp.raise_for_status()
        replayed = resp.headers.get("Idempotent-Replayed") == "true"
        if replayed:
            metrics.DUPLICATES_PREVENTED.inc()
        with self.engine.begin() as c:
            c.execute(
                text("UPDATE payouts SET status = 'sent', bank_ref = :b WHERE idempotency_key = :k"),
                {"b": resp.json().get("payout_id"), "k": key},
            )
        metrics.PAYOUTS.inc()
        log.info("payout sent", extra={"idempotency_key": key, "amount_cents": int(amount), "bank_replayed": replayed})
        return "paid"

    def handle(self, raw: bytes) -> None:
        job = json.loads(raw)
        rid_t = logging_setup.request_id_var.set(job.get("request_id"))
        jid_t = logging_setup.job_id_var.set(job.get("job_id"))
        metrics.IN_FLIGHT.set(1)
        start = time.perf_counter()
        try:
            outcome = self.process(job)
            self.ack(raw)
            metrics.JOBS.labels(outcome).inc()
        except Exception as e:  # noqa: BLE001 - any failure is retried with a cap
            log.warning(
                "job failed",
                extra={"error": f"{type(e).__name__}: {e}"[:300], "attempts": int(job.get("attempts", 0)) + 1},
            )
            self.retry_or_dead_letter(raw, job, type(e).__name__)
        finally:
            metrics.JOB_DURATION.observe(time.perf_counter() - start)
            metrics.IN_FLIGHT.set(0)
            logging_setup.request_id_var.reset(rid_t)
            logging_setup.job_id_var.reset(jid_t)

    # -- observability --------------------------------------------------------------------
    def update_gauges(self) -> None:
        now = time.time()
        metrics.QUEUE_DEPTH.set(self.r.llen(config.QUEUE))
        oldest = 0.0
        tail = self.r.lindex(config.QUEUE, -1)
        candidates = [tail] if tail else []
        for key in self.r.scan_iter(f"{config.PROCESSING_PREFIX}*"):
            candidates += self.r.lrange(key, 0, -1)
        for raw in candidates:
            try:
                oldest = max(oldest, now - float(json.loads(raw).get("enqueued_at", now)))
            except (ValueError, TypeError):
                continue
        metrics.QUEUE_OLDEST_AGE.set(oldest)
        with self.engine.connect() as c:
            dup = c.execute(
                text(
                    "SELECT count(*) FROM (SELECT 1 FROM payouts WHERE created_at > now() - interval '24 hours' "
                    "GROUP BY merchant_id, settlement_date HAVING count(*) > 1) d"
                )
            ).scalar()
        metrics.DUPLICATE_PAYOUTS.set(dup or 0)

    # -- main loop ------------------------------------------------------------------------
    def run(self) -> None:
        backoff = 0.5
        last_gauges = 0.0
        last_reap = 0.0
        while not _stop.is_set():
            self.heartbeat()
            try:
                now = time.monotonic()
                if now - last_reap > 30:
                    self.reap_orphans()
                    last_reap = now
                if now - last_gauges > 10:
                    self.update_gauges()
                    last_gauges = now
                raw = self.fetch()
                if raw is not None:
                    self.handle(raw)
                backoff = 0.5
            except Exception as e:  # noqa: BLE001 - dependency outage: back off, log rarely
                dep_log.error(
                    "loop", "worker loop error, backing off", error=f"{type(e).__name__}: {e}"[:300], backoff_s=backoff
                )
                _stop.wait(backoff + random.uniform(0, backoff / 2))
                backoff = min(backoff * 2, 30)
        log.info("drained, exiting")


def main() -> None:
    signal.signal(signal.SIGTERM, _handle_sigterm)
    signal.signal(signal.SIGINT, _handle_sigterm)
    start_http_server(config.WORKER_METRICS_PORT)
    r = redis.Redis.from_url(config.REDIS_URL, socket_timeout=5, socket_connect_timeout=3)
    log.info("worker starting", extra={"worker_id": WORKER_ID, "version": config.APP_VERSION})
    Worker(r).run()


if __name__ == "__main__":
    main()
