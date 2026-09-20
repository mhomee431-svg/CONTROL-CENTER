# PRODUCTION READINESS REPORT — Hyperlocal Customer App

**Prepared:** 2026-08-26
**Scope:** Full-repository audit (backend, customer app, shopkeeper app, database,
migrations, Docker, environment/config, auth, API, storage, Redis, search, background
jobs, notifications, payments, admin, shopkeeper, tests, CI/CD, infra, docs).
**Mode:** Audit only — **no large changes were implemented.** This report lists what is
in place, what is missing or broken, and every blocker that must be resolved before a
public AWS deployment.

> **Executive verdict:** the codebase is well-structured and feature-rich, but it is
> **not yet production-ready for a public, money-taking launch.** It is currently a
> development/QA stack that runs almost entirely in **mock mode**. The four things that
> must change first are: 1) rotate/purge committed secrets, 2) wire a real payment gateway
> (only mock exists), 3) add the missing `firebase-admin` dependency (FCM push is broken),
> and 4) move OTP + rate-limit state out of process memory (breaks under multi-instance
> autoscaling).

> **Audit refresh — 2026-08-27 (Phase 0 re-verified against the live repo):**
> - Phase 1 (Local Development Environment) is **implemented and committed** (HEAD commits
>   `9fb9793`, `42fa003`): dev scripts, Docker compose (PostGIS 16 + Redis 7), migrations,
>   health endpoints, `.env` profile auto-selection, and hardened startup checks.
> - Phase 2 (AWS Account & IAM Foundation) is **authored as IaC but UNCOMMITTED, UNAPPLIED
>   and UNTESTED** (untracked: `infrastructure/terraform/foundation/*`,
>   `infrastructure/scripts/iam_verify.ps1`, `infrastructure/scripts/install_tools.ps1`,
>   `.github/workflows/aws-iam-foundation.yml`, `docs/PHASE2_AWS_IAM_FOUNDATION.md`).
>   It holds S3 remote-state + DynamoDB lock, GitHub OIDC + scoped CI/CD role, operator /
>   monitoring / db-operator / S3-backup roles, and a bootstrap assume-role-only user. It is
>   blocked only on a **manually supplied AWS bootstrap connection** (account id + scoped
>   bootstrap key, applied from an internet-connected machine — this sandbox has no
>   outbound-download/AWS access). This addresses report blocker B4 *by design* but is not
>   yet exercised.
> - Blocker B1 remains OPEN: real `.env*` secret files still exist **on disk** under
>   `backend/`/`apps/customer_app/` (now untracked — removed from git history in `9fb9793`). They must
>   be rotated and eventually purged from history; only `.env.example` templates are tracked.
> - Blocker B2 remains OPEN: `firebase-admin` is **still absent** from `backend/requirements.txt`.
> - Phase 4 (RDS PostgreSQL + PostGIS) is **authored and statically validated but
>   UNAPPLIED/UNTESTED against a live AWS RDS instance** (this sandbox has no
>   Docker/AWS). Deliverables (untracked): `infrastructure/terraform/rds.tf` hardening
>   (deletion protection, auto minor upgrade, Performance Insights, Postgres log
>   export, endpoint outputs), `infrastructure/scripts/rds_migrate.sh` (safe
>   snapshot→migrate→verify workflow), `infrastructure/scripts/rds_restore.sh` (safe
>   snapshot-restore to a new instance), `backend/scripts/verify_rds.py` (live
>   PostGIS + approved-architecture verifier incl. rolled-back spatial sample),
>   `backend/tests/test_phase4_rds.py` (6 DB-free checks: migration chain HEAD
>   `0013`, PostGIS/pg_trgm enablement, Geography columns, verifier coverage),
>   and `docs/PHASE4_RDS_POSTGRESQL_POSTGIS.md`. PostGIS is already enabled by
>   committed migration `0002`; it is **not** recreated here. Applying Phase 4
>   requires the Phase 2 bootstrap + `terraform apply`, then `rds_migrate.sh`.
> - A **$0 managed-cloud Phase-4 path** is now also delivered
>   (`docs/PHASE4_FREE_CLOUD_POSTGRESQL_POSTGIS.md`): `scripts/provision_free_db.py`
>   provisions Neon/Supabase free tiers idempotently, `scripts/migrate_free_db.py`
>   runs the committed Alembic chain (0001→0013) + the verifier, and
>   `scripts/seed_free_data.py` seeds real Mumbai sample data through the ORM —
>   no RDS, no Docker, no cost.
> - All findings in §§5–15 below are **unchanged and still valid** at this refresh.

---

## 1. Current Architecture

Monorepo with four deliverables plus infrastructure:

```
hyperlocal_app/
├─ backend/          FastAPI monolith (Python 3.14), async SQLAlchemy
│  ├─ app/api/routes/     21 routers (customer, shopkeeper, admin, analytics, POS, subscription)
│  ├─ app/core/           config, security, storage, cache, celery, rate-limit, middleware,
│  │                      startup-checks, aws_secrets, upload_security, admin_permissions
│  ├─ app/models/         18 ORM model modules
│  ├─ app/services/       domain services (auth, otp, sms, email, push, notification, catalog,
│  │                      inventory, excel, barcode, pos, subscription, payments, analytics, audit)
│  ├─ app/search/         Postgres-backed search layer (normalizer, ranking, engine, indexer)
│  ├─ app/schemas/        Pydantic request/response contracts
│  ├─ alembic/versions/   migrations 0001 → 0011
│  ├─ tests/              21 backend test modules
│  └─ Dockerfile, docker-compose.yml, entrypoint.sh
├─ apps/customer_app/         Flutter **customer** app (Riverpod, Dio, flutter_secure_storage)
├─ apps/shopkeeper_app/    Flutter **shopkeeper** app (Riverpod, Dio, flutter_secure_storage)
├─ infrastructure/            Terraform — AWS topology (ECS Fargate web/worker/beat, RDS, ElastiCache,
│                    S3, ALB, Secrets Manager, IAM) + ecs_deploy.sh
├─ .github/workflows  backend-deploy, flutter-customer, flutter-shopkeeper
└─ scripts/          build_customer_prod.sh, build_shopkeeper_prod.sh
```

**Target runtime topology:** ALB (HTTPS) → ECS Fargate `web` (uvicorn) + `worker` +
`beat` (Celery) in private subnets → RDS PostgreSQL 16 (PostGIS) + ElastiCache Redis 7.
S3 private bucket (presigned URLs). Secrets in AWS Secrets Manager injected to ECS.

**Auth model:** phone-number OTP signup/login → JWT access + opaque hashed refresh token,
DB auth sessions, refresh rotation + reuse detection, token blacklist. Shared by customer
and shopkeeper via `auth.py` and `shopkeeper_auth.py`.

---

## 2. Existing Services (mapped to requested list)

| Area | Status | Where |
|---|---|---|
| Customer app (Flutter) | ✅ Discovery + auth + settings feature-rich | `apps/customer_app/` |
| Backend API | ✅ FastAPI monolith, layered | `backend/app` |
| Database | ✅ Postgres 16 + PostGIS, SQLAlchemy ORM | `models/`, migrations |
| Migrations | ✅ Alembic 0001→0011 (initial, expanded arch, catalog, shop, pricing, search+geo, import, POS, notifications, subscription, analytics) | `alembic/versions` |
| Docker | ✅ Multi-stage, non-root, health-checked image + compose (db/redis/api/worker/beat) | `backend/Dockerfile`, `docker-compose.yml` |
| Environment config | ✅ `.env.<env>` profiles + `.env.production.example` + pydantic-settings | `app/core/config.py`, `env.py` |
| Authentication | ✅ OTP + JWT + refresh rotation + sessions + blacklist | `auth.py`, `auth_service.py`, `security.py`, `otp_service.py` |
| API layer | ✅ 21 routers, Pydantic validation, envelope, pagination | `app/api/routes` |
| Storage layer | ✅ LocalDisk / S3 / Cloudinary (swappable) | `app/core/storage.py` |
| Redis integration | ✅ Cache wrapper + Celery broker/backend | `app/core/cache.py`, `celery_app.py` |
| Search integration | ⚠️ Postgres-only denormalized `search_indexes` + Celery sync; **no ES/OpenSearch/Meilisearch** | `app/search/*` |
| Background jobs | ✅ Celery worker + beat (index sync, popular searches, notification retry); ⚠️ email/SMS tasks are stubs | `app/services/tasks.py` |
| Notifications | ✅ DB notifications + async delivery, preferences, anti-spam; push=FCM\|mock (**FCM broken**) | `notification_service.py`, `push_service.py` |
| Payment integration | ⚠️ Contract + **Mock gateway only — no real gateway** | `services/payments/` |
| Admin functionality | ✅ API-only (no web UI): dashboard, users, shops, products, inventory, categories, brands, offers, subscriptions, payments, reports, analytics, complaints, feature flags, audit logs | `api/routes/admin.py`, `analytics_system.py` |
| Shopkeeper functionality | ✅ Flutter app + portal API (shops, products, inventory, POS, subscription) | `apps/shopkeeper_app/`, `shopkeeper_portal.py` |
| Tests | ✅ Backend 619; Customer 242; Shopkeeper 11 (reported). ⚠️ CI swallows failures | see Testing gaps |
| CI/CD | ⚠️ 3 workflows present; backend test step ignores failures (`\|\| true`) | `.github/workflows/*` |
| Documentation | ✅ README, infra README, API_CONTRACT, PHASE30/31 docs | |

## 3. Existing Services — quick inventory

- **Auth/identity**: JWT (HS256), sessions, OTP, RBAC + admin sub-role permissions.
- **Catalog / search / geo**: product masters, brands, categories, search engine + ranking + PostGIS geo.
- **Inventory**: price, availability, freshness, stock; 4 intake paths (manual/barcode/Excel/POS).
- **Notification** (push/email/SMS): typed notifications, dedupe, caps, device tokens; async delivery.
- **Subscription / payments**: plans, entitlements, payment ledger, webhooks (mock).
- **POS sync**: cron-like sync adapter (mock).
- **Admin / analytics / audit**: dashboards, reports, audit chain, analytics events.
- **Storage**: local/S3/Cloudinary with validation.

---

## 4. Missing Services

1. **Real payment gateway adapter (CRITICAL).** Only `MockPaymentProvider` is registered
   (`services/payments/__init__.py`, `mock_provider.py`). A public shopkeeper app cannot
   collect money. A production adapter (Razorpay/Stripe/Cashfree) + webhook + refund wiring
   is required; nothing registers an authenticated production gateway.
2. **Real POS vendor adapter.** Only `MockPOSProvider` (`services/pos_integration/*`).
3. **`firebase-admin` dependency absent (CRITICAL for FCM).** `push_service.py` calls
   `import firebase_admin` / `firebase_admin.messaging`, but `requirements.txt` has **no
   `firebase-admin` entry** → any `PUSH_PROVIDER=fcm` path raises `ImportError` at runtime.
4. **Explicit search engine (ES/OpenSearch/Meilisearch).** Search/geo is Postgres-only;
   acceptable at launch but there is no dedicated search cluster, and no third-party fuzzy
   suggest engine beyond the current ranking/normalizer layer.
5. **APM / error tracker.** No Sentry/Raygun/Rollbar (web) and no Crashlytics (apps);
   `main.dart` comments say "remote reporter pending" (documented accepted risk).
6. **Circuit breaker** for third-party calls (mitigated by retries only).
7. **Server-side image optimization** (no Pillow; relies on CDN transforms).
8. **Backup/recovery runbook & restore scripts** (referenced as operational, not in repo).
9. **Admin web dashboard UI.** Admin exists only as headless API — no admin frontend in the
   repo (only the two Flutter apps).
10. **Customer-app payment/order/money flows.** Monetization is shopkeeper-only; the customer
    app has no checkout or payment UI wired.

---

## 5. Duplicate Implementations

1. **`dispatch_email` / `dispatch_sms` Celery tasks are dead stubs** (`services/tasks.py`) —
   they log and return "queued" but **never call** the real `email_service`/`sms_service`.
   Two layers that do not talk to each other.
2. **Three storage providers** (Local/S3/Cloudinary) behind one factory (`core/storage.py`);
   S3 and Cloudinary overlap.
3. **Customer vs Shopkeeper apps duplicate** the Dio `ApiClient`, envelope-unwrap and auth
   pattern across `apps/customer_app/lib/core/network` and `apps/shopkeeper_app/lib/core/network`.
4. **Two OTP-based auth entry points** — `auth.py` + `shopkeeper_auth.py` share `otp_service`
   but are separately copied route modules.
5. **`aggregate_popular_searches`** defined in `app/search/engine.py` is scheduled through
   `app/services/tasks.py` — two paths to the same aggregation.
6. **`get_redis()` vs `Cache`** both expose raw Redis in `core/cache.py`.
7. **`MockProductRepository` still exists** in `backend/app/repositories/product_repository.py`
   and `get_product_repository()` returns the mock; the live products route bypasses it
   (Phase-4 leftover to prune).

---

## 6. Broken Implementations

1. **FCM push will not run** — `firebase-admin` is absent from `requirements.txt`
   (`push_service.py` imports it). CRITICAL for notifications.
2. **Email/SMS async dispatch stubs** — `dispatch_email`/`dispatch_sms` never invoke the
   provider (`services/tasks.py`, TODO).
3. **Real payments impossible** — only the Mock gateway is registered.
4. **OTP store is in-memory** (`_otp_store` dict in `otp_service.py`). With 1+ web instances
   behind the ALB, `/verify-otp` may hit a different instance → OTP "doesn't exist".
   **Breaks auth under autoscaling.**
5. **Rate-limit storage defaults to `memory://`** in production (per-worker counters);
   `.env.production.example` does not override it, so global limits are not enforced across
   workers.
6. **Cloudinary `delete_file` deletes by filename only** — brittle.
7. **Shopkeeper demo login** is guarded by `SHOPKEEPER_ENABLE_DEMO_LOGIN` (default false) and
   production CI sets it false — safe by default, but a backdoor if ever built with the flag on.
8. **Celery `get_redis()` can spawn a second connection** when `_redis is None`; a
   pre-existing duplication, not a crash.


---

## 7. Security Risks

| Severity | Risk | Evidence | Required action |
|---|---|---|---|
| **CRITICAL** | **Real secrets committed to git history** (`backend/.env*`, `apps/customer_app/.env`) | Files were tracked (present in commit `7b357c0`) and only removed via staged `git rm --cached`; files still on disk. | Rotate **every** credential that ever sat in these files (JWT secret, DB password, SMS/email/storage keys), or purge history (`filter-repo`/BFG). **Blocking before public exposure.** |
| **HIGH** | **No real payment provider** → monetization impossible; mock gateway signs with a **shared literal default secret** `mock-payment-secret` | `mock_provider.py` `DEFAULT_MOCK_SECRET`; only `code="MOCK"` registered | Real gateway + secrets; never expose the mock in prod |
| **HIGH** | **FCM credential/`firebase-admin` gap** | `push_service.py` needs `firebase_admin` not listed in `requirements.txt` | Add dependency + supply service-account JSON via Secrets Manager |
| **MED** | Startup security gate does not verify provider readiness (only JWT/OTP/DEBUG/CORS/rate-limit) | `startup_checks.py` | Extend to fail-fast when STORAGE/SMS/EMAIL/PUSH/PAYMENT are still "mock" or missing creds in prod |
| **MED** | `CORS_ORIGINS` defaults to wildcard combined with `allow_credentials=True` | `main.py` `allow_origins = cors_origin_list or ["*"]`; gate flags only in prod | Set explicit origins in ECS config (infra does set it — verify never empty) |
| **MED** | Rate-limit counters per-worker (`memory://`) → cross-instance abuse not throttled at the declared cap | `rate_limit.py` `memory://` default | Use a shared Redis DB for `RATE_LIMIT_STORAGE_URI` in prod |
| **MED** | OTP in-memory → brute-force lockout and OTP are per-instance, lost on restart | `otp_service.py` `_otp_store` | Move to Redis with TTL + attempt counters |
| **LOW** | `OTP_DEV_MODE` default true + universal `123456` | `config.py` | Startup gate enforces off in prod (already done) |
| **LOW** | JWT HS256 with `JWT_SECRET_KEY` default "change-me-in-production" | `config.py` | Startup gate refuses prod boot (already done) |
| **LOW** | `S3_ACL` default `public-read` in code (infra sets private) | `config.py` | Ensure ECS sets private; keep objects private |

**Good posture already present:** parameterized SQL end-to-end, auth + global rate limits,
magic-byte upload validation, HSTS/security headers, request/correlation-ID middleware, JWT
claims + refresh rotation + blacklist, OTP salted-HMAC storage, and no static secrets in the
runtime image.

---

## 8. Deployment Blockers (must resolve before `terraform apply` / CI deploy)

- **[B1] Rotate secrets / purge history** (CRITICAL).
- **[B2] `requirements.txt` missing `firebase-admin`** → live push broken.
- **[B3] Real payment adapter + gateway params** not provided.
- **[B4] Terraform state is LOCAL** — the S3 backend block is commented out
  (`providers.tf`). Deploying from CI/multiple machines risks concurrent-apply drift; enable
  remote state + DynamoDB lock.
- **[B5] CI test step swallows failures** — `pytest ... \|\| true` means deploy proceeds
  even when tests fail (`.github/workflows/backend-deploy.yml`). Fail on error instead.
- **[B6] No automated migration step on deploy** — migrations run via a manual
  `aws ecs run-task ... alembic upgrade head` (infrastructure/README), so a bad migration can ship
  with code. Gate migrations on deploy.
- **[B7] `RATE_LIMIT_STORAGE_URI`, `TRUST_X_FORWARDED_FOR`, and OTP-in-Redis** still default
  to in-memory; must be surfaced into ECS env.
- **[B8] Search-index sync depends on Redis** (Celery router + indexer). If Redis is down,
  catalog writes fail to enqueue and the index goes stale until it returns (mitigated by
  background reconcile). Flag as accepted operational risk.
- **[B9] `terraform.tfvars.example` uses placeholder `example.com`**; real values are manual.

---

## 9. Database Blockers

1. **OTP is not distributed / persistent** — breaks multi-instance auth (ties to B7).
2. **Search `search_indexes` denormalized table** must stay in sync; drift is reconciled only
   by the periodic Celery incremental + hourly reconcile. A stale Redis/Celery delay makes
   listings briefly invisible.
3. **Rate-limit counters** need Redis DB #3 (not RDS) for global enforcement.
4. **PostGIS Geography** is stubbed to Text in SQLite tests; on real RDS the `postgis`
   extension must be present (`enable_postgis()` at startup handles it) — verify on first deploy.
5. **No schema-drift detector** — `alembic stamp head` can silently diverge from the ORM and
   cause runtime SQLAlchemy errors. Validate `upgrade head` against a fresh DB on first deploy.


---

## 10. API Blockers

- **Payments are mock-only** — `subscribe`, `payments/initiate`, `payments/verify`,
  `payments/refund` and webhooks all route through `MockPaymentProvider`.
- **Async notification** relies on `dispatch_email`/`dispatch_sms` tasks that currently
  **log only** — the API reports success but nothing is actually delivered.
- **Push** — FCM crashes from the missing `firebase-admin` dependency.
- **Admin authorization** — `require_admin` (super-role) is used on most admin endpoints
  while granular `require_admin_permission` (sub-roles) exists but is not uniformly applied
  across all admin routes.
- **Sync DB sessions inside `async def` handlers** (`Depends(get_db)`) is present across
  many routes; functional, but worth a review for connection efficiency under load.

---

## 11. Flutter Blockers

**Customer app (`apps/customer_app/`)**
- `apiBaseUrl` has **no default** — the app fails fast unless `API_BASE_URL` is injected.
  Production CI injects it (`flutter-customer.yml`); safe, but there is no fail-over check
  if the value is accidentally empty.
- `MockAuthRepository` is selected when `API_BASE_URL` is empty (local/dev only). Not a prod
  risk because CI sets the URL, but the mock must never leak into a release build.
- No cart/checkout/payment UI in the customer app (discovery-focused).
- Crash logging is a placeholder (`SafeLogger`) — no Sentry/Crashlytics attached.
- Uses `flutter_secure_storage` for tokens — good.

**Shopkeeper app (`apps/shopkeeper_app/`)**
- Demo login is guarded by `SHOPKEEPER_ENABLE_DEMO_LOGIN` (default false) and production CI
  sets false — safe, but it is a hard-coded-credential backdoor if ever built with the flag on.
- No analytics/device-token registration wiring surfaced to the app settings in a way that
  uses the production push path.

---

## 12. Testing Gaps

- Backend **619 passed / 6 skipped** (PHASE31) but **CI swallows failures** with `\|\| true`
  (blocker B5).
- No test exercising a **real payment gateway** (mock only).
- No distributed/multi-worker test for **OTP in Redis** (in-memory is fine locally, not for
  2+ workers).
- No smoke test that **`firebase-admin` installs and FCM initializes** — this gap allowed the
  missing-dependency defect to go uncaught.
- No integration test for a **real SMS/email provider**.
- Infra (Terraform) is **not exercised** — no `terraform validate`/`plan` in CI.
- Frontend tests are **widget/unit only**; CI builds Android APK only (no iOS build/tests).
- No **contract tests** enforcing that the customer/shopkeeper apps match the frozen
  `API_CONTRACT.md`.
- Phase-31 adds only 7 E2E tests; no customer-app-to-real-API smoke test.

---

## 13. External Dependencies (runtime)

- PostgreSQL 16 + PostGIS
- Redis ≥6 (currently 7) — cache, Celery broker/result, and (needed) rate-limit store
- AWS: RDS, ElastiCache, S3, Secrets Manager, ECR, ECS/Fargate, ALB (via IAM, no static keys)
- Celery / uvicorn / FastAPI / SQLAlchemy / pydantic / slowapi / python-jose / passlib
- SMS: Twilio (or MSG91 / AWS SNS)
- Email: SMTP / SendGrid / AWS SES
- Push: Firebase Cloud Messaging (`firebase-admin` — **needs adding**)
- Storage: S3 (required for prod)
- Payments: gateway key (Razorpay / Stripe — **a real one required**)
- Maps: Google Maps API key (customer app) + geocoding

> Many of these are currently **not wired** (SMS/EMAIL/PUSH/POS/PAYMENTS run on mock), so the
> system works locally/for demos but is not connected to paid/real providers. See the
> Security and Missing-Services sections.

---

## 14. Required Manual Inputs (per infrastructure/README + terraform.tfvars.example)

Must be provisioned **before** `terraform apply`:

1. **AWS account + IAM role** for Terraform (least-privilege); export
   `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` as env vars (never in files); choose region
   (e.g. `ap-south-1`).
2. **Domain + Route53 hosted zone** (or point `api.` A-record to the ALB DNS after apply).
3. **Provider keys**, then paste into the **Secrets Manager** backend bundle as flat JSON:
   `JWT_SECRET_KEY` (long random), `SMS_PROVIDER` + Twilio/`TWILIO_AUTH_TOKEN`,
   `SENDGRID_API_KEY`, FCM service-account JSON, payment gateway keys,
   `OTP_DEV_MODE=false`, `STORAGE_PROVIDER=s3` (+ S3 bucket/region).
4. `DATABASE_URL` is auto-injected by `rds.tf` (do not hand-paste it).
5. **Run migrations** (documented): `aws ecs run-task --task-definition <web> --overrides '... alembic upgrade head'`.
6. **Health check**: `curl https://api.<domain>/health` then `/ready`.
7. **Flutter build-time values**: `CUSTOMER_API_BASE_URL`, `SHOPKEEPER_API_BASE_URL`,
   `MAPS_API_KEY` (customer app) — injected via `--dart-define` in CI.

---

## 15. Recommended Priority (after this audit — no changes made yet)

1. Rotate/purge committed secrets (blocker B1).
2. Add `firebase-admin`, wire Sentry/Crashlytics; enable real SMS/EMAIL/push providers.
3. Implement a **real payment gateway** adapter + params (with a GAiT plan).
4. Move **OTP + rate-limit counters to Redis**; set `RATE_LIMIT_STORAGE_URI` and
   `TRUST_X_FORWARDED_FOR` in production.
5. Fix CI: fail on test errors (remove `\|\| true`) and gate migrations on deploy.
6. Enable the Terraform **S3 backend + DynamoDB lock**; wire a migrate step into the pipeline.
7. Optionally build an admin web UI (headless API already exists).
8. Strengthen the startup gate to verify **provider readiness** (reject "mock" providers /
   missing creds in prod).

---

*This document is a snapshot-only audit; per instruction, **no code changes were made** to
services, routes, models, or infra.*
- **Infrastructure**: ECS, RDS, Redis, S3, Secrets Manager, ALB, autoscaling.