# settle

Daily merchant settlement service (settle-api + settle-worker).

> **Reconstruction notice.** No source repository or evidence bundle was supplied with the
> Project Tidewater brief. This first commit is a *reconstruction* of the inherited
> repository, built from the facts in the brief (FastAPI + gunicorn with 4 workers,
> Redis-backed worker with retries, Postgres 15 `max_connections=100`, nginx ingress,
> migration 0008 shipped in v1.8.0). The defects in it are the ones the incident symptoms
> in the brief imply. Every later commit is a fix on top of it.
