# syntax=docker/dockerfile:1
#
# Hyperlocal Customer API — production runtime image (Phase 10).
#
# Single-stage, non-root, health-checked. ALL secrets arrive at runtime via
# environment / AWS Secrets Manager (entrypoint) — nothing is baked in.
#
# Image optimization:
#   * python:3.14-slim — minimal base; no build toolchain needed because every
#     dependency ships a cp314 binary wheel (psycopg[binary], asyncpg, bcrypt…)
#   * installs requirements.prod.txt — runtime-only deps, no pytest tooling
#   * NO curl/wget — the HEALTHCHECK uses the Python stdlib instead, dropping
#     the apt layer (and a general-purpose network tool) from the image
#   * dependency layer is cached independently of the application layer
#   * .dockerignore keeps env files, credentials, tests, docs and logs out of
#     the build context
#
# Build (from repo root):  docker build -t hyperlocal-backend:latest Backend
# Run (local stack):       docker compose -f Backend/docker-compose.yml up --build

FROM python:3.14-slim AS runtime

LABEL org.opencontainers.image.title="hyperlocal-backend" \
      org.opencontainers.image.description="Hyperlocal Customer API — production runtime" \
      org.opencontainers.image.source="https://github.com/Akasharyan47/hyperlocal_customer_app"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_DEFAULT_TIMEOUT=100

WORKDIR /app

# Non-root application user (least privilege inside the container).
RUN adduser --system --ingroup root --disabled-password --home /app appuser

# Install Python deps first for better layer caching (runtime-only set).
COPY requirements.prod.txt ./
RUN pip install --no-cache-dir --requirement requirements.prod.txt

# Copy the application (entrypoint.sh, alembic/, app/ — tests, docs, scripts,
# env files and credentials are excluded via .dockerignore).
COPY . .

# The app writes uploads/logs relative to /app; hand ownership to appuser.
RUN mkdir -p /app/storage /app/logs \
    && chown -R appuser:root /app

USER appuser

EXPOSE 8000

# Liveness/readiness — /ready verifies DB, Redis and PostGIS.
# Uses the stdlib (urlopen raises on non-2xx), so no curl in the image.
HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/ready', timeout=4)" || exit 1

# Entrypoint optionally (a) hydrates env from AWS Secrets Manager,
# (b) runs Alembic migrations, then execs the real command (CMD) — the exec
# keeps the app as PID 1 so `docker stop` delivers SIGTERM straight to
# uvicorn/celery for graceful shutdown (in-flight requests drained, Redis and
# DB pools closed by the app lifespan before exit).
ENTRYPOINT ["/bin/sh", "/app/entrypoint.sh"]

# Default: run the API server. Override CMD for worker/beat/migrate.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2", "--proxy-headers", "--forwarded-allow-ips", "127.0.0.1,172.16.0.0/12"]