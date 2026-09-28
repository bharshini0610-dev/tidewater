# syntax=docker/dockerfile:1.7
# Build context is the repository root (the image also carries migrations/ for the
# pre-deploy migration Job).
#
# Changes vs. inherited image: pinned base instead of python:latest, multi-stage build
# (no compilers in the runtime image), non-root user, no DATABASE_URL/password baked in,
# no `COPY . .` of the whole tree (.env files, tests, .git), logs to stdout instead of
# /var/log/settle, exec-form CMD so gunicorn is PID 1 and receives SIGTERM, and a gunicorn
# timeout above the slowest legitimate request.
ARG PYTHON_IMAGE=python:3.12-slim-bookworm

FROM ${PYTHON_IMAGE} AS build
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /build
COPY app/requirements.txt .
RUN python -m venv /venv && /venv/bin/pip install --no-cache-dir -r requirements.txt

FROM ${PYTHON_IMAGE}
ARG APP_VERSION=dev
ARG SOURCE_URL=https://github.com/bharshini0610-dev/tidewater
LABEL org.opencontainers.image.title="settle-api" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.source="${SOURCE_URL}"
# hadolint ignore=DL3005,DL3008
RUN apt-get update && apt-get upgrade -y --no-install-recommends && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 10001 settle \
    && useradd --system --uid 10001 --gid settle --no-create-home --shell /usr/sbin/nologin settle
COPY --from=build /venv /venv
WORKDIR /app
COPY --chown=root:root app/settle ./settle
COPY --chown=root:root app/gunicorn.conf.py ./
COPY --chown=root:root migrations ./migrations
ENV PATH=/venv/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    APP_VERSION=${APP_VERSION} \
    MIGRATIONS_DIR=/app/migrations \
    PROMETHEUS_MULTIPROC_DIR=/tmp/prom
USER 10001:10001
EXPOSE 8000
CMD ["sh", "-c", "mkdir -p \"$PROMETHEUS_MULTIPROC_DIR\" && rm -f \"$PROMETHEUS_MULTIPROC_DIR\"/*.db && exec gunicorn -c gunicorn.conf.py settle.api:app"]
