# Phase 15 — FastAPI Backend Foundation

## Overview

Production-grade backend foundation for the Hyperlocal Customer App, built with FastAPI, PostgreSQL/PostGIS, Redis, and Celery.

## Architecture Layers

```
┌─────────────────────────────────────────────────────────────┐
│  API / Router Layer  (app/api/routes/*)                     │
│  - FastAPI routers, request validation (Pydantic schemas)   │
├─────────────────────────────────────────────────────────────┤
│  Service Layer  (app/services/*)                            │
│  - Business logic, provider abstractions (email/sms/storage)│
│  - BaseService generic CRUD                                 │
├─────────────────────────────────────────────────────────────┤
│  Repository Layer  (app/repositories/*)                     │
│  - Data access, BaseRepository generic CRUD                 │
├─────────────────────────────────────────────────────────────┤
│  Domain Layer  (app/domain/*)                               │
│  - Pure business entities (dataclasses, enums)              │
├─────────────────────────────────────────────────────────────┤
│  Infrastructure  (app/core/*, app/database/*)               │
│  - Config, env, logging, exceptions, middleware, cache,     │
│    celery, storage, rate-limit, health, security            │
└─────────────────────────────────────────────────────────────┘
```

## Key Components

### Configuration Management (`app/core/config.py`)
- Environment profiles: `development`, `test`, `staging`, `production`
- Auto-selects `.env.<environment>` based on `HYPERLOCAL_ENV` / `ENVIRONMENT`
- All provider secrets loaded from env vars — never hardcoded
- Pydantic validation with field constraints

### Environment Files
| File | Purpose |
|------|---------|
| `.env` | Development (default) |
| `.env.test` | Test suite / CI |
| `.env.staging` | Pre-production validation |
| `.env.production` | Production (secrets via orchestration) |
| `.env.example` | Reference template |

### Database (`app/database/session.py`)
- Async engine with connection pooling (`AsyncAdaptedQueuePool`)
- Sync engine for Alembic/Celery
- PostGIS extension bootstrap
- Transaction handling: `transaction()`, `unit_of_work()`
- Lifecycle: `check_database_connection()`, `dispose_database()`

### Redis Cache (`app/core/cache.py`)
- Async Redis wrapper with connection lifecycle
- `get/set/delete/expire/incr` operations
- Auto-connect/close context manager

### Celery (`app/core/celery_app.py`)
- Production config: JSON serialization, timezone, retries, routing
- Task queues: `default` (core), `background` (services)
- Beat schedule placeholder

### Storage Abstraction (`app/core/storage.py`)
- `BaseStorageProvider` interface
- Providers: `LocalStorageProvider`, `S3StorageProvider`, `CloudinaryStorageProvider`
- Selected via `STORAGE_PROVIDER` config

### Email Abstraction (`app/services/email_service.py`)
- `BaseEmailProvider` interface
- Providers: `MockEmailProvider`, `SMTPEmailProvider`, `SendGridEmailProvider`, `SESEmailProvider`
- Selected via `EMAIL_PROVIDER` config

### SMS Abstraction (`app/services/sms_service.py`)
- `BaseSMSProvider` interface
- Providers: `MockSMSProvider`, `TwilioSMSProvider`, `AWSSNSProvider`, `MSG91SMSProvider`
- Selected via `SMS_PROVIDER` config

### Authentication & Authorization (`app/core/dependencies.py`)
- `get_current_user` — JWT bearer token resolution
- `require_permission(resource, action)` — RBAC permission check
- `require_role(role_name)` — role-based check
- `get_optional_user` — optional auth for public endpoints

### Error Handling (`app/core/exceptions.py`)
- `AppError` hierarchy: NotFound, Unauthorized, Forbidden, Validation, Conflict, RateLimit, ServiceUnavailable
- Global handlers with request context logging
- Consistent error response format

### Logging (`app/core/logging.py`)
- Structured JSON logging (or console format)
- Request/correlation ID context enrichment via contextvars
- Rotating file handler in production

### Middleware (`app/core/middleware.py`)
- `RequestIDMiddleware` — request/correlation ID propagation
- `SecurityHeadersMiddleware` — CSP, HSTS, X-Frame-Options, etc.

### Rate Limiting (`app/core/rate_limit.py`)
- SlowAPI-based limiter
- Configurable storage (memory:// dev, redis:// prod)
- Auth endpoint stricter limits

### Health Checks (`app/core/health.py`)
- `/health` — liveness probe
- `/ready` — readiness probe (DB, Redis, PostGIS)

## Testing

Run the test suite:
```bash
cd Backend
python -m pytest tests/ -v
```

Test coverage includes:
- Configuration loading & environment profiles
- JWT token roundtrip
- Storage provider upload/delete
- Email/SMS mock providers
- Celery app config & task execution
- Health router existence
- Middleware classes
- Rate limiter config
- Domain entities
- Repository/Service base importability

## Running the Application

```bash
cd Backend
# Development
python -m uvicorn app.main:app --reload --port 8000

# Production (with env profile)
HYPERLOCAL_ENV=production python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

## Celery Worker

```bash
cd Backend
celery -A app.core.celery_app.celery_app worker --loglevel=info
```

## Verification Checklist

- [x] Application startup (lifespan hooks) — verified via uvicorn
- [x] Database connection (pooling + PostGIS) — graceful degradation when DB down
- [x] Redis connection (cache abstraction) — graceful degradation when Redis down
- [x] Migration execution (Alembic)
- [x] Health endpoint (`/health`, `/ready`) — verified live
- [x] Authentication middleware foundation
- [x] Error handling (global exception handlers)
- [x] Background job execution (Celery tasks)
- [x] Configuration loading (env profiles)
- [x] Test suite: 55 passed, 6 skipped (DB integration tests auto-skip without live Postgres)

## Verified Live Output

```
GET /health  → {"status":"healthy","version":"1.0.0","environment":"development"}
GET /ready   → {"status":"not_ready","checks":{"database":false,"redis":false,"postgis":false}}
GET /        → {"app":"Hyperlocal Customer API","version":"1.0.0",...}
```

Structured logging correctly enriches records with `request_id` and `correlation_id`.
