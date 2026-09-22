# Hyperlocal Platform

Hyperlocal product discovery: search any product and instantly see which nearby
shop/mall has it, at what price, whether it's available, and how far away it is.

The repo is a **monorepo**: each app owns its responsibilities independently,
while genuinely-shared contracts and models live in versioned packages under
`packages/` (never a dumping ground - see the governance rules below).

## Repository layout

| Path | Contents |
|------|----------|
| `apps/customer_app/` | Flutter **customer** app (Riverpod, Dio, flutter_secure_storage) |
| `apps/shopkeeper_app/` | Flutter **shopkeeper** app |
| `apps/admin_panel/` | Flutter web **admin** console (verification, moderation, analytics) |
| `backend/` | FastAPI + PostgreSQL/PostGIS + Redis + Celery API (single source of truth for all contracts) |
| `packages/api_contracts/` | HTTP contract: hand-written `API_CONTRACT.md` + **generated** `openapi.json` (CI-checked, never hand-edited) |
| `packages/shared_models/` | Pure-Dart shared models (API envelope, pagination) used by all three apps |
| `infrastructure/terraform/` | Terraform (AWS ECS/RDS/ElastiCache, `foundation/` + `free/` stacks) |
| `infrastructure/scripts/` | Deployment, migration & backup scripts |
| `scripts/` | Local dev & build helper scripts |
| `storage/` | Local uploads (dev object storage) |
| `docs/` | Platform documentation (see taxonomy below) |

### Dependency rule (what keeps `packages/` clean)

````
apps/*  -->  packages/*  -->  (nothing - leaf packages)
````

- `packages/shared_models` is pure Dart, imports nothing from any app, and
  only holds models consumed by **two or more apps**.
- The backend's Pydantic schemas are the source of truth; Dart DTOs mirror
  them. `packages/api_contracts/openapi.json` is regenerated from the app via
  `python backend/scripts/export_openapi.py` and CI fails on drift.

## Branches and environments

```
feature/*  --PR-->  develop  --auto deploy-->  staging  --smoke + E2E-->  PR
                      |                                                    |
                      +------------------- main <-------------------------+
                                            |
                                  approval -> production (EC2/ECS + RDS + S3)
```

| Branch | Deploys to | Gate before it goes further |
|--------|-----------|------------------------------|
| `feature/*` | nothing (local only) | backend CI + Flutter analyze/test on the PR |
| `develop` | **staging** automatically | quality battery → smoke battery → E2E contract battery |
| `main` | **production** after approval | everything above + required reviewers on the `production` environment |

`develop` is a *git branch* (which code); `staging` is an *environment* (where it
runs). Full rules, required status checks, variables, runbooks and rollback
procedures: [`docs/deployment/BRANCHING.md`](docs/deployment/BRANCHING.md).

```powershell
# start work
git switch develop && git pull && git switch -c feature/<name>

# prove a deployed environment serves the committed contract (no credentials)
python infrastructure/scripts/cicd_contract_check.py `
  --url https://staging-api.hyperlocal.in --expect-env staging

# apply the branch protection rules (needs a PAT in $env:GITHUB_TOKEN)
powershell -ExecutionPolicy Bypass -File scripts/setup_branch_protection.ps1 -DryRun
```

## Quick start (local development)

**Prerequisite:** Docker Desktop (runs PostgreSQL/PostGIS 16-3.4 + Redis 7).
See [`backend/docs/PHASE1_LOCAL_DEVELOPMENT.md`](backend/docs/PHASE1_LOCAL_DEVELOPMENT.md)
for the full toolchain matrix and detailed setup.

````powershell
# 1. One-command reproducible backend setup (venv + deps + PostGIS/Redis + migrations)
powershell -ExecutionPolicy Bypass -File scripts/dev/setup.ps1

# 2. Start the backend (infra up + migrate + uvicorn --reload on :8000)
powershell -ExecutionPolicy Bypass -File scripts/dev/dev.ps1

# 3. Verify
Invoke-RestMethod http://localhost:8000/ready   # -> {"status":"ready", ...}
#    API docs:  http://localhost:8000/docs

# 4. Flutter customer app
cd apps/customer_app
flutter pub get
flutter run
````

Full stack (mirrors AWS topology, validates the container images):

````powershell
powershell -ExecutionPolicy Bypass -File scripts/dev/stack.ps1 up
# or directly:  docker compose -f backend/docker-compose.yml up --build
````

Run the backend tests:

````powershell
powershell -ExecutionPolicy Bypass -File scripts/dev/test.ps1
````

## Docs

| Area | Docs |
|------|------|
| Architecture | [`docs/architecture/`](docs/architecture/) - [ARCHITECTURE.md](docs/architecture/ARCHITECTURE.md), [gap report](docs/architecture/ARCHITECTURE_GAP_REPORT.md), [AWS architecture](docs/architecture/AWS_ARCHITECTURE.md) |
| Database | [`docs/database/`](docs/database/) - schema design, RDS/PostGIS, free-cloud Postgres, backup & recovery, migration automation |
| API | [`docs/api/API_OVERVIEW.md`](docs/api/API_OVERVIEW.md) + full contract in [`packages/api_contracts/`](packages/api_contracts/) |
| Security | [`docs/security/`](docs/security/) - secrets management, IAM foundation, Firebase phone auth |
| Deployment | [`docs/deployment/`](docs/deployment/) - [branching & release gates](docs/deployment/BRANCHING.md), CI/CD, ECS deploy, domain/HTTPS, runbook, DR, cost guide |
| Testing | [`docs/testing/`](docs/testing/) - real-device E2E protocol |

Backend-specific phase docs live in [`backend/docs/`](backend/docs/).

## Configuration

Environment profiles are auto-selected (`HYPERLOCAL_ENV` > `ENVIRONMENT` >
`development`) and mapped to `.env.<profile>` files. Templates are committed
(`backend/.env.example`, `backend/.env.production.example`); real secrets are
**never** committed and live in OS env vars / AWS Secrets Manager.