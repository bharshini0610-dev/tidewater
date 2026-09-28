"""Structured JSON logging to stdout.

Why: the inherited code logged DEBUG to /var/log/settle on a hostPath volume with no
rotation. During the incident the reconnect loop wrote to that file until the node hit
DiskPressure. Logs now go to stdout only (the kubelet rotates container logs), as one
JSON object per line, carrying the request_id so a request can be followed from nginx
through the API into the worker.
"""

import contextvars
import json
import logging
import os
import sys
import time

request_id_var: contextvars.ContextVar[str | None] = contextvars.ContextVar("request_id", default=None)
job_id_var: contextvars.ContextVar[str | None] = contextvars.ContextVar("job_id", default=None)

_RESERVED = set(vars(logging.makeLogRecord({})).keys()) | {"message", "asctime"}


class JsonFormatter(logging.Formatter):
    def __init__(self, service: str):
        super().__init__()
        self.service = service

    def format(self, record: logging.LogRecord) -> str:
        out = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(record.created)) + f".{int(record.msecs):03d}Z",
            "level": record.levelname,
            "service": self.service,
            "logger": record.name,
            "msg": record.getMessage(),
        }
        if (rid := request_id_var.get()) is not None:
            out["request_id"] = rid
        if (jid := job_id_var.get()) is not None:
            out["job_id"] = jid
        for k, v in record.__dict__.items():
            if k not in _RESERVED and not k.startswith("_"):
                out[k] = v
        if record.exc_info:
            out["exc"] = self.formatException(record.exc_info)
        return json.dumps(out, default=str)


class _StdoutHandler(logging.StreamHandler):
    """Resolve sys.stdout at emit time (works under gunicorn re-exec and test capture)."""

    @property
    def stream(self):
        return sys.stdout

    @stream.setter
    def stream(self, _value):
        pass


def setup(service: str) -> None:
    handler = _StdoutHandler()
    handler.setFormatter(JsonFormatter(service))
    root = logging.getLogger()
    root.handlers[:] = [handler]
    root.setLevel(os.environ.get("LOG_LEVEL", "INFO").upper())
    # Access logs are produced by our middleware (with request_id); silence the duplicates.
    logging.getLogger("uvicorn.access").disabled = True
    logging.getLogger("gunicorn.access").disabled = True


class RateLimitedLogger:
    """Emit at most one record per `interval` seconds for a repeating error.

    A dependency outage produces the same error thousands of times a second in a tight
    loop; we log the first one and then a counter, never an unbounded stream.
    """

    def __init__(self, logger: logging.Logger, interval: float = 30.0):
        self.logger = logger
        self.interval = interval
        self._last: dict[str, float] = {}
        self._suppressed: dict[str, int] = {}

    def error(self, key: str, msg: str, **extra) -> bool:
        now = time.monotonic()
        last = self._last.get(key)
        if last is not None and now - last < self.interval:
            self._suppressed[key] = self._suppressed.get(key, 0) + 1
            return False
        suppressed = self._suppressed.pop(key, 0)
        self._last[key] = now
        self.logger.error(msg, extra={**extra, "suppressed_since_last": suppressed})
        return True
