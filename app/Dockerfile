FROM python:latest
WORKDIR /app
COPY . .
RUN pip install -r requirements.txt
RUN mkdir -p /var/log/settle
ENV DATABASE_URL=postgresql+psycopg://settle:S3ttle-prod-2026@postgres:5432/settle
CMD gunicorn settle.api:app -k uvicorn.workers.UvicornWorker -w 4 -b 0.0.0.0:8000 --timeout 5
