# PHASE 11 — Backend AWS Deployment

**Date:** 2026-08-31
**Scope:** Deploy the backend to AWS on the existing free-tier architecture;
verify the full production checklist (start, API, DB, Redis, S3, auth, logs,
health); wire deploy + rollback tooling.

---

## 1. Architecture decision (simplest production-safe, no over-engineering)

The account already runs the **free-tier single-instance topology** (Phase 3
network foundation + Phase 4 RDS). Recreating an ECS/ALB/NAT design would cost
money and duplicate what exists, so Phase 11 deploys **on the existing
architecture**:

```
Flutter app
   ↓ HTTPS/HTTP :80/:443
Elastic IP 13.234.167.97 (SG: only 80/443 open, no SSH — SSM Session Manager)
   ↓
Caddy (systemd, auto-TLS when a domain is attached) → 127.0.0.1:8000
   ↓
Docker Compose stack (Backend/docker-compose.cloud.yml)
   ├── migrate  (one-shot: alembic upgrade head, EXITS)
   ├── api      (uvicorn, 1 worker, mem 512m)   restart: unless-stopped
   ├── worker   (celery, concurrency 2)          restart: unless-stopped
   ├── beat     (celery scheduler)               restart: unless-stopped
   └── redis    (redis:7-alpine, AOF, 96mb cap)  restart: unless-stopped
   ↓ private network
   ├── RDS PostgreSQL 16 + PostGIS (db.t3.micro, private data subnet,
   │   publicly_accessible=false, creds via SSM SecureString)
   ├── S3 uploads bucket (private, TLS-only policy, via S3 Gateway endpoint
   │   + instance IAM role — no static keys)
   └── Redis: local container (ElastiCache has no free tier)
```

**Staging:** a staging environment does **not exist** (no staging Terraform
state, no staging resources). Standing one up would need a second EC2 + RDS,
which exceeds the 12-month free tier. Per the phase rule "deploy staging first
**if staging exists**" — it does not, so production is the deploy target.
`terraform.tfvars.staging.example` + separate state key remain the documented
path when a second environment is wanted.

## 2. Requirements → implementation

| Requirement | Implementation |
|---|---|
| Deployment | Git-commit-driven: `infra/scripts/deploy_backend.sh deploy [ref]` on the instance (fetch → `git reset --hard` → `compose build/up`) |
| Env vars / secrets | `Backend/.env` written at boot from SSM SecureString (`DATABASE_URL`), generated `JWT_SECRET_KEY` (0600 perms), S3 config; GitHub PAT in SSM. Nothing baked into images |
| Health checks | App: `/health` (liveness) + `/ready` (DB + Redis + PostGIS). Image: Dockerfile `HEALTHCHECK` on `/ready`. Deploy: `/ready` poll with 180 s budget |
| Auto restart | `restart: unless-stopped` on api/worker/beat/redis; Docker + Caddy `systemctl enable` at boot |
| Logs | JSON request logs in-app; container logs with rotation (`json-file`, 10 MB × 3); boot log via `journalctl -t hyperlocal-boot`; VPC flow logs in CloudWatch |
| Resource limits | `mem_limit`/`cpus` per service: api 512m/0.75, worker 384m/0.50, beat 128m/0.25, redis 128m/0.25 (in-Redis maxmemory 96mb), migrate 384m |
| Scaling foundation | Stateless api container (uploads → S3, OTP/rate-limit state → Redis, DB → RDS) = the prerequisite for horizontal scale; scale-up path documented in `infra/README.md` (ECS+ALB design preserved in git history) |
| Rollback | Deploy script records `LAST_GOOD_SHA` before every deploy; failed health check auto-rolls back; manual `rollback` subcommand |

## 3. Incident found & fixed during deployment

The first boot **never started the API** (Caddy → 502): the one-shot `migrate`
service set `RUN_MIGRATIONS=true` but kept the default image CMD, so after
`alembic upgrade head` the entrypoint exec'd **uvicorn** — the "one-shot"
never exited, and api/worker/beat (gated on
`service_completed_successfully`) stayed in `Created` forever.

**Fix (all three compose files):** migrate now runs an explicit
`command: ["alembic", "upgrade", "head"]` with `RUN_MIGRATIONS=false`, so the
container exits 0 and releases the dependency gate.

## 4. Deployment runbook

```bash
# On the app instance (EC2 Console → Connect → Session Manager):
cd /opt/hyperlocal
./infra/scripts/deploy_backend.sh deploy          # latest origin/main
./infra/scripts/deploy_backend.sh status          # sha + container states
./infra/scripts/deploy_backend.sh verify          # health battery

./infra/scripts/deploy_backend.sh rollback        # back to LAST_GOOD_SHA
```

Failed health check during `deploy` → automatic rollback (exit 1 on failure).
Build failures leave the running stack untouched (old containers keep serving).

## 5. Verification results (2026-08-31, production)

Live checks run against `http://13.234.167.97` and the instance via SSM.

| Check | Method | Result |
|---|---|---|
| Backend starts | `docker compose ps` — api/worker/beat Up, redis healthy; migrate exited 0 | ✅ |
| API responds | `GET /health` 200, `GET /ready` 200, `GET /openapi.json` 200 from the internet | ✅ |
| Database works | `/ready` → `database:true`; `alembic current` → **0013 (head)** | ✅ |
| Redis works | `/ready` → `redis:true`; `redis-cli ping` in container → **PONG** | ✅ |
| S3 works | put/get/delete round-trip on `hyperlocal-935173128886-uploads` with the instance role (no static keys) | ✅ |
| Auth works | `POST /api/v1/auth/send-otp` → 200 (`expires_in:300`, code stored in Redis db4, dev mode off); wrong OTP → **400** | ✅ |
| Logs work | Structured JSON app logs in `docker logs api` (request/correlation IDs); boot log via `journalctl -t hyperlocal-boot` | ✅ |
| Health check | `/health`, `/ready`, image `HEALTHCHECK` → `healthy`; **Caddy → API 200** | ✅ |

**Auto-restart validation:** the instance was deliberately rebooted (`ec2
reboot-instances`). The whole stack came back on its own — Docker and Caddy
`systemctl enable`, `restart: unless-stopped`, and the idempotent boot script
re-ran `compose up -d --build` — and `/health` returned 200 without manual
intervention. ✅ (This is the scaling/autorestart foundation: a stateless,
restartable, idempotent single-node deployment.)

## 6. Notes & follow-ups

- **Secrets on the server:** `Backend/.env` holds the runtime secret (DB URL,
  generated JWT key). It is root-only (`umask 077`) and never committed; DB
  access is via RDS creds in SSM SecureString. The GitHub PAT was stored in
  SSM (`/hyperlocal/production/github_token`) and the server remote uses it for
  `git fetch`; rotate it if compromised.
- **worker/beat HEALTHCHECK:** the production image ships a `HEALTHCHECK`
  probing `:8000/ready` (for the API). Since celery never serves that port,
  `docker-compose.cloud.yml` sets `healthcheck: disable: true` on
  worker/beat so they are not falsely flagged unhealthy.
- **JWT secret persistence** (`user_data.sh.tpl`): the secret is now reused
  from the existing `.env` on rebuild instead of regenerated, so instance
  replaces don't invalidate every user token (cloud-init runs only at first
  boot, so a plain reboot already preserved `.env`).
- **Free-tier ceiling:** a second (staging) environment would need its own
  EC2 + RDS, which exits the 12-month free tier — the documented upgrade path
  (ECS Fargate + ElastiCache) is preserved in `infra/README.md`.
