"""gunicorn settings for settle-api.

timeout: the inherited image used --timeout 5 while /reports/daily legitimately takes 6-9 s,
so gunicorn killed its own workers mid-request (nginx logged 502 "upstream prematurely
closed"). It is now above the slowest legitimate request, and the report has its own
statement_timeout.
keepalive: must be longer than nginx's upstream keepalive_timeout, otherwise nginx reuses
a connection gunicorn has just closed and returns a 502.
"""

import os

from prometheus_client import multiprocess

bind = "0.0.0.0:8000"
workers = int(os.environ.get("GUNICORN_WORKERS", "4"))
worker_class = "uvicorn_worker.UvicornWorker"
timeout = int(os.environ.get("GUNICORN_TIMEOUT", "30"))
graceful_timeout = int(os.environ.get("GUNICORN_GRACEFUL_TIMEOUT", "25"))
keepalive = 75
max_requests = 5000
max_requests_jitter = 500
accesslog = None  # access logs come from the app middleware as JSON with request_id
errorlog = "-"
worker_tmp_dir = "/tmp"  # noqa: S108 - emptyDir; root filesystem is read-only


def child_exit(_server, worker):
    if os.environ.get("PROMETHEUS_MULTIPROC_DIR"):
        multiprocess.mark_process_dead(worker.pid)
