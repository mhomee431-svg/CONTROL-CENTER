# Phase 1 - Local Development Environment

This document defines a **reproducible local development setup** for the
Hyperlocal Customer App monorepo and records the verified state of the current
machine.

---

## 1. Required toolchain & verified versions

| Tool            | Required                                                    | Verified on this machine | Status |
|-----------------|-------------------------------------------------------------|--------------------------|--------|
| Python          | 3.14 (matches `backend/Dockerfile`, CI workflow)            | 3.14.3                   | OK     |
| Node.js         | Tooling only (Flutter tooling / CI) - no app `package.json` | v16.20.2                 | OK     |
| Flutter         | stable channel                                              | 3.47.0 (stable)          | OK     |
| Dart            | `^3.13.0` (`apps/customer_app/pubspec.yaml`)                         | 3.13.0                   | OK     |
| Android SDK     | Android toolchain (for device builds)                       | 37.0.0 (`flutter doctor` OK) | OK |
| Git             | >= 2                                                        | 2.53.0                   | OK     |
| **Docker**      | Required to run PostgreSQL/PostGIS + Redis                  | **NOT INSTALLED**        | GAP    |
| **Docker Compose** | Required (v2 subcommand)                                | **NOT AVAILABLE**        | GAP    |
| PostgreSQL      | 16 + PostGIS 3.4 (via `postgis/postgis:16-3.4` image)       | **NOT INSTALLED**        | GAP    |
| Redis           | 7 (via `redis:7-alpine`)                                    | **NOT INSTALLED**        | GAP    |

> **Gap on this machine:** Docker, Docker Compose, PostgreSQL, PostGIS and
> Redis are the **only** missing prerequisites. Everything else is present and
> verified. The API container targets **Python 3.14**, and the installed
> interpreter matches, so **no dependency upgrades were needed**.

### Backend Python dependencies

All packages in `backend/requirements.txt` are already satisfied (no random
upgrades applied). Verified installs include: `fastapi 0.141.1`,
`uvicorn 0.52.4`, `SQLAlchemy 2.0.52`, `alembic 1.19.1`, `psycopg 3.3.4`,
`asyncpg 0.31.0`, `GeoAlchemy2 0.20.0`, `pydantic 2.13.4`,
`pydantic-settings 2.15.0`, `redis 8.1.0`, `celery 5.6.3`, `pytest 9.1.1`,
`httpx 0.28.1`, `slowapi 0.1.10`, `structlog`, `boto3`, `cloudinary`.

---

## 2. Install Docker first

The data services (PostgreSQL + PostGIS + Redis) are containerised so the whole
team gets the *same* database engine and PostGIS version. Install once:

1. Install **Docker Desktop** (enable the WSL2 backend on Windows).
2. Start Docker Desktop and wait for the engine (whale icon steady).
3. Verify in a terminal:
   ```powershell
   docker --version
   docker compose version
   ```
   Both must print a version instead of "not recognized".

> **Alternative (no Docker):** install PostgreSQL 16 with the **PostGIS**
> add-on and a Redis 7 server (or Memurai on Windows) directly, and point
> `DATABASE_URL` / `REDIS_URL` in `backend/.env` at them. Docker is
> recommended because it pins matching versions for the whole team.

### Why infra-only vs full stack?

- `backend/docker-compose.infra.yml` - **PostGIS + Redis only** (fast, native
  `uvicorn --reload` development). **Recommended for daily coding.**
- `backend/docker-compose.yml` - full production-shaped stack
  (db + redis + api + worker + beat). Use it to validate the exact container
  images used in ECS.
- **Do not run both at once** - both bind host ports 5432 and 6379.

---

## 3. One-command reproducible setup

Windows (PowerShell):

```powershell
powershell -ExecutionPolicy Bypass -File scripts/dev/setup.ps1
```

macOS / Linux / WSL:

```bash
bash scripts/dev/setup.sh
```

`setup` is **idempotent** (safe to re-run). It will:
1. Create `backend/.venv` and install `requirements.txt` (if needed).
2. Create `backend/.env` from `.env.example` **only if absent** (never overwrites).
3. Start the PostGIS + Redis infra stack via `docker-compose.infra.yml`.
4. Wait for containers to become healthy.
5. Run `alembic upgrade head` (all 11 migrations, 0001 -> 0011).

### Verify the toolchain

```powershell
powershell -ExecutionPolicy Bypass -File scripts/dev/check_environment.ps1
```

Prints each tool's detected version against its requirement and reports whether
PostgreSQL (5432) and Redis (6379) are listening.

---

## 4. Documented start commands

### A. Native backend (recommended for iteration) - two terminals

**Terminal 1 - start infra + migrations + API (one command):**

```powershell
powershell -ExecutionPolicy Bypass -File scripts/dev/dev.ps1
```

Runs the infra stack, `alembic upgrade head`, then
`uvicorn app.main:app --reload --port 8000`.

**Terminal 1 (manual equivalent):**

```powershell
cd backend
docker compose -f docker-compose.infra.yml up -d
.\.venv\Scripts\Activate.ps1
alembic upgrade head
uvicorn app.main:app --reload --port 8000
```

**Terminal 2 - hit the API / health checks:**

```powershell
# Readiness: DB/Redis/PostGIS reachable + migrations applied:
Invoke-RestMethod http://localhost:8000/ready
# Liveness (always 200 when the process is alive):
Invoke-RestMethod http://localhost:8000/health
# API root / metadata:
Invoke-RestMethod http://localhost:8000/
# Interactive docs:  http://localhost:8000/docs
# API request example (health-scoped, no auth):
Invoke-RestMethod http://localhost:8000/api/v1/categories
```

`/ready` should report:

```json
{ "status": "ready", "checks": { "database": true, "redis": true, "postgis": true } }
```

### B. Full production-shaped stack (validate the exact container images)

```powershell
docker compose -f backend/docker-compose.yml up --build
```

This boots `db`, `redis`, `api`, `worker`, and `beat` together, mirroring the
AWS ECS topology.

### C. Flutter customer app

```powershell
cd Frontend
flutter pub get
flutter run          # on a connected device / emulator / Chrome
```

Configure the API base URL in `apps/customer_app/lib/core/config/env_config.dart`
(point it at `http://localhost:8000` for local dev). The shopkeeper app lives
in `apps/shopkeeper_app/` (same commands).

---

## 5. What was tested (state of this machine, no Docker)

The following were executed and **passed** on this machine without a data
service running:

| Check | Command | Result |
|-------|---------|--------|
| Backend imports | `python -c "import app.main"` | OK, env=development |
| Health (liveness) | `GET /health` | OK, `status: healthy` |
| Root metadata | `GET /` | OK, app/version/env/docs |
| Readiness shape | `GET /ready` | OK 200, `not_ready` (db/redis/postgis false - expected, infra down) |
| Migrations compile | `alembic upgrade head --sql` | OK, generated full offline SQL 0001->0011 |
| Offline test suite | `pytest tests/test_foundation.py` | OK, 20 passed |
| Test collection | `pytest --collect-only` | OK, 625 tests collect |
| Flutter deps | `flutter pub get` (Frontend) | OK, resolved |
| Android toolchain | `flutter doctor` | OK, SDK 37.0.0 (VS Windows target incomplete - not needed for Android) |

**Not yet run (require Docker infra):** live DB connection, PostGIS version
query, Redis ping, `alembic upgrade head` against a live DB, and the full
red/green pytest suite. These become green after step 2 (Docker) is done and
`scripts/dev/setup.ps1` is run.

---

## 6. Running the tests

```powershell
# Full suite (needs the infra stack up):
powershell -ExecutionPolicy Bypass -File scripts/dev/test.ps1

# Subset by keyword (works offline for logic-level modules):
powershell -ExecutionPolicy Bypass -File scripts/dev/test.ps1 -Filter foundation

# Or directly:
cd backend
.\.venv\Scripts\Activate.ps1
pytest -q
```

> `backend/tests/conftest.py` forces `ENVIRONMENT=test`, which reads
> `backend/.env.test` (`DATABASE_URL=...hyperlocal_test`, Redis on 6379/0).
> DB/Redis-backed test modules (e.g. `test_database_schema.py`,
> `test_e2e_phase31.py`) require the infra stack so the `hyperlocal_test`
> database is reachable.

---

## 7. Local object storage

Development uses the **local filesystem** provider (`STORAGE_PROVIDER=local`,
`STORAGE_LOCAL_PATH=./storage/uploads` in `backend/.env`). Uploaded files are
written under `backend/storage/uploads/` and served via `/static/uploads/...`.
No S3/MinIO is required locally. Swap to S3/Cloudinary only for staging/prod.

---

## 8. Configuration reference

| File | Purpose |
|------|---------|
| `backend/.env.example` | Reference template (committed, no secrets) |
| `backend/.env` | **Development** (default profile; git-ignored) |
| `backend/.env.test` | Pytest / CI (git-ignored) |
| `backend/.env.staging` / `.env.production` | Staging / production (git-ignored) |
| `.env.production.example` | Prod reference (committed, no secrets) |
| `backend/docker-compose.yml` | Full production-shaped stack |
| `backend/docker-compose.infra.yml` | Local PostGIS + Redis only (added in Phase 1) |
| `backend/Dockerfile`, `entrypoint.sh` | Container build + boot |

Profile selection: `HYPERLOCAL_ENV` > `ENVIRONMENT` > default `development`;
the matching `.env.<env>` (or `.env`) file is loaded automatically by
`app/core/config.py`. Never commit real secrets - `.env*` is git-ignored and
only `*.example` templates are tracked.

---

## 9. Troubleshooting

- **`docker: command not found`** -> install Docker Desktop, start it, then re-run setup.
- **`/ready` shows `not_ready`** -> infra is down:
  `docker compose -f backend/docker-compose.infra.yml up -d`, wait for `healthy`.
- **Port 5432/6379 already in use** -> another Postgres/Redis is bound; stop it
  or change the compose `ports` mapping and the matching URL in `backend/.env`.
- **`alembic upgrade head` fails** -> confirm the DB container is `healthy`
  (`docker compose -f backend/docker-compose.infra.yml ps`).
- **PowerShell blocks scripts** -> run with `-ExecutionPolicy Bypass` as shown.


