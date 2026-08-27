# syntax=docker/dockerfile:1
#
# Hyperlocal Customer API — production runtime image.
#
# Multi-stage, non-root, health-checked. Reads ALL secrets from the
# environment (injected by ECS Secrets Manager / entrypoint) — nothing is
# baked into the image.
#
# Build:        docker build -t hyperlocal-backend:latest -f Backend/Dockerfile .
# Run (local):  docker compose -f Backend/docker-compose.yml up

FROM python:3.14-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_DEFAULT_TIMEOUT=100

WORKDIR /app

# Minimal system deps. psycopg[binary] bundles libpq; keep curl for the
# container HEALTHCHECK only.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

# Non-root application user (least privilege inside the container).
RUN adduser --system --ingroup root --disabled-password --home /app appuser

# Install Python deps first for better layer caching.
COPY requirements.txt ./
RUN pip install --no-cache-dir --requirement requirements.txt

# Copy the application.
COPY . .

# The app writes uploads/logs relative to /app; hand ownership to appuser.
RUN chown -R appuser:root /app \
    && mkdir -p /app/storage /app/logs \
    && chown -R appuser:root /app/storage /app/logs

USER appuser

EXPOSE 8000

# Liveness/readiness — /ready verifies DB, Redis and PostGIS.
HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8000/ready || exit 1

# Entrypoint optionally (a) hydrates env from AWS Secrets Manager,
# (b) runs Alembic migrations, then execs the real command (CMD).
COPY entrypoint.sh /app/entrypoint.sh
ENTRYPOINT ["/bin/sh", "/app/entrypoint.sh"]

# Default: run the API server. Override CMD for worker/beat/migrate.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2", "--proxy-headers", "--forwarded-allow-ips", "*"]