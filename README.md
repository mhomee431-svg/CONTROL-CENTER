# Hyperlocal Customer App

Hyperlocal product discovery: search any product and instantly see which nearby
shop/mall has it, at what price, whether it's available, and how far away it is.

## Repository layout

| Path | Contents |
|------|----------|
| `Backend/` | FastAPI + PostgreSQL/PostGIS + Redis + Celery API (customer, shopkeeper, admin) |
| `Frontend/` | Flutter **customer** app (Riverpod, Dio, flutter_secure_storage) |
| `ShopkeeperApp/` | Flutter **shopkeeper** app |
| `infra/` | Terraform + deployment scripts (AWS ECS/RDS/ElastiCache) |
| `scripts/` | Dev & build helper scripts |
| `storage/` | Local uploads (dev object storage) |

## Quick start (local development)

**Prerequisite:** Docker Desktop (runs PostgreSQL/PostGIS 16-3.4 + Redis 7).
See [`Backend/docs/PHASE1_LOCAL_DEVELOPMENT.md`](Backend/docs/PHASE1_LOCAL_DEVELOPMENT.md)
for the full toolchain matrix and detailed setup.

```powershell
# 1. One-command reproducible backend setup (venv + deps + PostGIS/Redis + migrations)
powershell -ExecutionPolicy Bypass -File scripts/dev/setup.ps1

# 2. Start the backend (infra up + migrate + uvicorn --reload on :8000)
powershell -ExecutionPolicy Bypass -File scripts/dev/dev.ps1

# 3. Verify
Invoke-RestMethod http://localhost:8000/ready   # -> {"status":"ready", ...}
#    API docs:  http://localhost:8000/docs

# 4. Flutter customer app
cd Frontend
flutter pub get
flutter run
```

Full stack (mirrors AWS topology, validates the container images):

```powershell
powershell -ExecutionPolicy Bypass -File scripts/dev/stack.ps1 up
# or directly:  docker compose -f Backend/docker-compose.yml up --build
```

Run the backend tests:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/dev/test.ps1
```

## Docs

- [Phase 1 - Local Development Environment](Backend/docs/PHASE1_LOCAL_DEVELOPMENT.md)
- [Phase 2 - AWS Account & IAM Foundation](docs/PHASE2_AWS_IAM_FOUNDATION.md)
- [Phase 3 - AWS Network Foundation](docs/PHASE3_AWS_NETWORK_FOUNDATION.md)
- [Phase 4 - RDS PostgreSQL + PostGIS](docs/PHASE4_RDS_POSTGRESQL_POSTGIS.md)
- [Phase 4 - **Free** cloud PostgreSQL + PostGIS (Neon/Supabase, $0)](docs/PHASE4_FREE_CLOUD_POSTGRESQL_POSTGIS.md)
- [Phase 5 - Database Backup & Recovery](docs/PHASE5_DATABASE_BACKUP_RECOVERY.md)
- [Free-tier cloud deployment (LIVE now)](docs/FREE_TIER_CLOUD.md)
- [API contract](Backend/docs/API_CONTRACT.md)
- [Production hardening](Backend/docs/PHASE30_PRODUCTION_HARDENING.md)
- [E2E platform testing](Backend/docs/PHASE31_E2E_PLATFORM_TESTING.md)
- [Phase 25 - CI/CD](docs/PHASE25_CICD.md)
- [Phase 26 - Database Migration Automation](docs/PHASE26_DATABASE_MIGRATION_AUTOMATION.md)
- [Production readiness report](PRODUCTION_READINESS_REPORT.md)

## Configuration

Environment profiles are auto-selected (`HYPERLOCAL_ENV` > `ENVIRONMENT` >
`development`) and mapped to `.env.<profile>` files. Templates are committed
(`Backend/.env.example`, `Backend/.env.production.example`); real secrets are
**never** committed and live in OS env vars / AWS Secrets Manager.
