# Cloud Ownership & Capability Matrix

> **Companion document:** [`CLOUD_OWNERSHIP.md`](CLOUD_OWNERSHIP.md) holds the
> narrative source of truth for the same audit — the auth rationale, credential
> isolation, the overlap/redundancy register and the architecture-decision log.

> **Single source of truth for infrastructure ownership in this monorepo.**
> Every capability below maps to exactly ONE owning provider/service.
> Last verified by repository discovery: 2026-09-25 (branch `develop`).

Governing rule: **convenience never decides architecture.** Before adding a
service, confirm in this table that the capability is unowned, and record the
decision here. Refactor and repair — never delete a working feature, endpoint,
UI component, or DB model to make room for a new provider.

---

## 1. Capability Matrix

| Capability | Owning Provider / Service | Reason / Spec |
|---|---|---|
| Relational Data | **AWS RDS PostgreSQL + PostGIS** | Spatial integrity for geo search (`GeoAlchemy2`, `ST_DWithin`/`ST_Within`), SQLAlchemy 2.0 async models, Alembic chain `0001..0026` |
| Object Storage | **AWS S3** (private bucket) | Presigned direct-upload pipeline; AWS credentials never reach the client (`app/api/routes/media.py`) |
| Image / Media Processing | **AWS Lambda** | Event-driven `ObjectCreated` processing (`backend/lambda_function.py`) via S3 → EventBridge → Lambda |
| Secrets | **AWS Secrets Manager** (prod) / env files (dev) | `app/core/aws_secrets.py` hydrates a JSON secret bundle at container start; no secret literals in git or in any Flutter app |
| Push Notifications | **Firebase Cloud Messaging (FCM)** | Backend-triggered alerts (`PUSH_PROVIDER=fcm`, `app/services/push_service.py`); the same service account also serves Firebase Auth |
| Auth — identity proof | **Firebase** (Phone Auth + Google Sign-In) | Client obtains a Firebase ID token; `app/services/firebase_verification.py` verifies it server-side |
| Auth — session & authorization | **FastAPI + Custom Role JWT** | The backend issues its own short-lived access + rotated refresh tokens and enforces the dual-app RBAC engine (`app/core/dependencies.py`) |
| Cache / Rate limiting / OTP store | **Redis** (self-hosted or ElastiCache) | `app/core/cache.py`; Redis is never the source of truth — PostgreSQL stays authoritative |
| Background jobs | **Celery** on Redis | Async work (notifications, indexing) decoupled from request latency |
| Inbound webhooks | **FastAPI** + HMAC-SHA256 | `app/api/routes/webhooks.py`; shared-secret signature with a replay window |
| Observability / Audit | **AWS CloudWatch + CloudTrail**, hash-chained in-app `audit_logs` | `app/core/observability/cloudtrail.py`; admin mutations write an immutable trail |
| Search & Geo | **PostgreSQL/PostGIS** | Geo queries live in SQL; no external search engine (deliberate — see §3) |

---

## 2. Per-Provider Discovery Findings

### Firebase — what it is used for, and why
Used for **three** things, all identity/notification:

1. **Phone Auth (OTP)** — the Flutter apps call `firebase_auth` directly; Google
   sends the SMS, so no third-party SMS gateway is needed for customer login.
2. **Google Sign-In** — ID token exchanged at `POST /api/v1/auth/google-login`.
3. **FCM** — server-triggered push.

Artifacts found: `apps/customer_app/android/app/google-services.json`
(Android only), `firebase_core` / `firebase_auth` / `firebase_messaging` in
`pubspec.yaml`, `firebase-admin>=6.5.0` in both `requirements.txt` and
`requirements.prod.txt`.

**Credential isolation — verified compliant.** The only Firebase file in the
repo is the Android *public* client config, which is designed to ship. The
service-account private key is never in the repo: the backend loads it from
`FIREBASE_CREDENTIALS_FILE` / `FIREBASE_CREDENTIALS_JSON` (fed by Secrets
Manager) and falls back to Application Default Credentials.

### AWS — what it is used for, and why
`boto3` is used for: Secrets Manager (`app/core/aws_secrets.py`), S3 media
storage, CloudTrail/IAM observability, and the S3 event Lambda. Terraform lives
under `infrastructure/`. `docs/deployment/FREE_TIER_CLOUD.md` documents the
deliberate $0-window topology (single EC2 t3.micro running PostGIS + Redis +
API in Docker, no NAT Gateway/ALB/RDS/ElastiCache) ≈ **$12.80/month** covered by
the $100 signup credit (~7.8 months).

### GCP

---

## 3. Redundancy Flags (per governance: flag immediately)

These are **intentional provider abstractions, not defects** — but each is a
place where two providers can serve the same capability, so the owner is pinned
below and the alternates must stay unset in production.

| Capability | **Owner** | Alternates present in config | Status |
|---|---|---|---|
| OTP delivery | **Firebase Phone Auth** | Legacy Redis-backed `otp_service` (`OTP_STORAGE_URI`, `OTP_MAX_ATTEMPTS`) | ⚠️ **Two live OTP paths.** The legacy service is legacy-path tuning only; Firebase owns delivery. Do not enable both. |
| Object storage | **AWS S3** | `cloudinary` (`STORAGE_PROVIDER`) | ⚠️ Unset in prod. Remove the flag only after a deprecation window — not yet. |
| Email | **SendGrid** | `smtp` (aiosmtplib), `aws-ses` | Pick one; SES costs extra permissions. |
| SMS (non-auth) | **Twilio** | `aws-sns`, `mock` | Firebase already covers auth SMS; Twilio is for transactional only. |
| Payments | **Mock provider (dev only)** | none registered | ⚠️ `MOCK_PAYMENT_SECRET` default is refused at boot by the startup security gate. Blocked for prod. |

**Explicitly NOT a redundancy:** custom JWT vs Firebase Auth. Firebase *proves
identity*; FastAPI *issues sessions and enforces RBAC*. Both are required — the
backend must own authorization to serve three apps (customer, shopkeeper,
admin) with a single permission model.

---

## 4. Security Controls

- **Fail-closed startup gate** — `app/core/startup_checks.py` refuses to boot in
  production with: default `JWT_SECRET_KEY`, `DEBUG=true`, wildcard CORS,
  in-memory rate-limit store, FCM enabled without credentials, or the mock
  payment provider with its default secret.
- **Short-lived tokens** — access 30 min, refresh 30 days with rotation +
  reuse detection; `iss`/`aud`/`jti`/`type` claims and a token blacklist.
- **Private-by-default objects** — `S3_ACL=private`; reads go through
  short-lived presigned GETs minted after an authorization check.
- **Upload hardening** — magic-byte sniffing blocks renamed/polyglot uploads;
  per-category byte caps; short upload-URL lifetimes.
- **Audit** — every critical admin mutation writes a hash-chained `audit_logs`
  row plus an `admin_actions` companion.
- **Repo hygiene** — `scripts/security/scan_secrets.py` + bandit run in CI.

### Known open risk (not yet fixed)
`docs/deployment/PRODUCTION_READINESS_REPORT.md` records that real secrets were
committed in history (commit `7b357c0`) and only untracked later. **Rotate every
credential that ever appeared in `backend/.env*` / `apps/customer_app/.env`
before any public exposure**, or purge history with `filter-repo`/BFG.

---

## 5. Cost Visibility & Budget Alerts

Paid-capable features in this repo, with free-tier limits:

| Feature | Free tier | Budget alert |
|---|---|---|
| EC2 t3.micro | 750 h/mo (12 mo) | $10 warn / $25 alert / $50 critical |
| RDS db.t3.micro + storage | 750 h/mo + 20 GB (12 mo) | as above |
| S3 | 5 GB, 20k GET, 2k PUT (12 mo) | as above |
| ElastiCache / ECS Fargate / ALB | **no free tier** | hold disabled until Stage B |
| FCM | 1M messages/mo free (Spark plan) | $0 at current volume |
| CloudWatch Logs | 5 GB/mo ingestion free | included in alerts |

Terraform resources are tagged `Project=Hyperlocal`,
`Environment=production|staging|dev`, `ManagedBy=Terraform` for cost
allocation. The current $0-window topology costs ≈$12.80/month against a $100
credit.

---

## 6. Contract Drift Watch

`packages/api_contracts` (`openapi.json` + `API_CONTRACT.md`) is the contract
source of truth for the three Flutter apps. `packages/shared_models` holds the
Dart envelope models (`api_envelope.dart`, `paginated_envelope.dart`) that must
mirror the Pydantic response envelopes in `backend/app/schemas/`. When a
Pydantic schema changes, regenerate/verify the contract **and** the Dart models
in the same change — a silent mismatch surfaces as a runtime decode error in the
apps, not as a compile error.

**No GCP dependency.** No `google-cloud-*` packages, no Terraform GCP provider,
no service-account wiring. GCP appears only as a *client* SDK (Google Maps /
Geocoding) and as the OAuth identity provider behind Firebase. This is a
deliberate single-cloud outcome.
