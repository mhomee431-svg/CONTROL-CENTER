# Phase 10 — Backend Dockerization

Production-safe Docker configuration for the backend API, with environment
separation, an optimized image, and the full runtime verification checklist.

## Files

| File | Purpose |
|---|---|
| `backend/Dockerfile` | Production runtime image (single-stage, non-root, stdlib healthcheck) |
| `backend/entrypoint.sh` | Secrets hydration (AWS Secrets Manager) → migrations → `exec` CMD |
| `backend/requirements.prod.txt` | Runtime-only dependencies (no pytest tooling in the image) |
| `backend/.dockerignore` | Keeps env files, credentials, tests, docs, scripts, logs out of the build context |
| `backend/docker-compose.infra.yml` | **Development** — PostGIS + Redis only (backend runs natively with `uvicorn --reload`) |
| `backend/docker-compose.yml` | **Staging-shaped local stack** — db + redis + migrate + api + worker + beat |
| `backend/docker-compose.free.yml` | **Staging on the free-tier EC2** (`infrastructure/free` Terraform boot) |
| `backend/docker-compose.cloud.yml` | **Production** on the single EC2 (private RDS + local Redis + Caddy) / ECS parity |
| `scripts/test_docker_phase10.ps1` | Automated verification checklist (build, startup, DB/Redis/S3/health, graceful shutdown) |

## Environment separation

The image is identical everywhere; behavior is selected purely by environment
configuration (12-factor — no rebuild per environment):

- **development** — `backend/.env` (`ENVIRONMENT=development`, OTP dev mode on,
  docs enabled), infra via `docker-compose.infra.yml`, app run natively.
- **staging** — `backend/.env.staging` (`ENVIRONMENT=staging`, OTP dev mode
  **off**, S3 storage, docs enabled), full stack via `docker-compose.yml`
  (`ENVIRONMENT=staging` default) or `docker-compose.free.yml` on EC2.
- **production** — `backend/.env.production` (`ENVIRONMENT=production`,
  docs disabled automatically, OTP dev mode off, Redis-backed OTP/rate-limit
  stores), deployed via `docker-compose.cloud.yml` or ECS
  (`infrastructure/scripts/ecs_deploy.sh`); secrets injected by the entrypoint from
  AWS Secrets Manager (`USE_AWS_SECRETS=true`).

## Image optimization

- `python:3.14-slim` base — no compiler toolchain required (all deps ship
  cp314 binary wheels).
- `requirements.prod.txt` installs **runtime-only** dependencies; pytest /
  pytest-asyncio / pytest-cov never enter the image. `httpx` stays (used at
  runtime by Fast2SMS and Google OAuth). Provider SDKs (boto3, cloudinary,
  sendgrid, twilio, aiosmtplib, firebase-admin) stay because they are lazily
  imported by the replaceable provider modules.
- No `curl`/`wget`/apt packages — the Docker `HEALTHCHECK` uses the Python
  standard library, removing the apt layer and a general-purpose network tool.
- Dependency layer is copied and installed before the application layer for
  build-cache hits on code-only changes.
- `.dockerignore` excludes: `.env*` (except `.env.example`), Firebase service
  account JSON, `*.pem/*.key/*.jks/*.keystore/*.p12`, tests, docs, ops
  scripts, logs, uploads, caches.

## Security posture

- **No secrets in the image** — env files are dockerignored; production
  secrets arrive via the entrypoint from AWS Secrets Manager
  (`python -m app.core.aws_secrets --export`, values never logged).
- **No local databases** — no DB files/data are baked in; state lives in the
  PostGIS/Redis containers (staging) or private RDS (production).
- **Non-root runtime** — the app runs as the system user `appuser`
  (`USER appuser`); `/app/storage` and `/app/logs` are writable by it.
- **Fail-fast posture** — production startup gate (`app.core.startup_checks`)
  refuses insecure configuration (dev OTP, insecure JWT secrets).
- **Unnecessary tools excluded** — no shell utilities beyond the slim base,
  no test runners, no editor/OS junk.

## Runtime behavior

- **Health check** — Docker `HEALTHCHECK` polls `/ready` (verifies DB, Redis,
  PostGIS) every 30s with a 90s start period; `/health` is the liveness probe.
- **Environment configuration** — all configuration via environment variables
  (`.env.<environment>` per profile; `HYPERLOCAL_ENV`/`ENVIRONMENT` select the
  profile at import time).
- **Graceful shutdown** — the entrypoint `exec`s the server (PID 1 =
  uvicorn/celery), so `docker stop` SIGTERM reaches the app directly; uvicorn
  drains in-flight requests, the lifespan hook closes the Redis cache first
  then disposes DB pools, and compose files grant `stop_grace_period` 30–45s.

## Verification

Docker is **not available in this development environment**, so the runtime
checklist ships as an executable script. On any machine with Docker Desktop
or a Docker Engine:

```powershell
# from the repo root
powershell -ExecutionPolicy Bypass -File scripts/test_docker_phase10.ps1
```

The script performs and asserts: clean build (`--no-cache`), clean startup on
fresh volumes, `pg_isready`, `redis-cli ping`, S3 `head_bucket` (skipped with
a clear reason when `STORAGE_PROVIDER=local`), `GET /health`, `GET /ready`
(all sub-checks true), and graceful-shutdown log verification.

Static validation performed locally: all four compose files parse as valid
YAML; the Dockerfile instructions were reviewed for context/path correctness
(build context is `backend/`); the offline unit suites for Redis resilience
and secrets hygiene (`backend/tests/test_redis_phase6.py`,
`backend/tests/test_secrets_management_phase8.py`) pass in this workspace.
