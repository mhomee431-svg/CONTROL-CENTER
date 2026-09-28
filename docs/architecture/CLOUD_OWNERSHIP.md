<<<<<<< HEAD
# Cloud Ownership — Single Source of Truth

**Status:** authoritative for provider/service ownership across the monorepo.
**Primary AWS region:** `ap-south-1` (Mumbai).
**Last audited:** from live code discovery (`google-services.json` presence,
`pubspec.yaml`, `backend/requirements.txt`, `boto3` call sites,
`app/core/config.py`, `app/core/aws_secrets.py`, `deploy.sh`, `infrastructure/`).

> Rule: a capability must have **exactly one** owning provider. If two providers
> can serve one capability, this document records which is canonical and flags
> the other as legacy — it is never silently removed (see §6).

---

## 1. Discovery findings

Discovery was run before any change, per §3 of the operating charter.

### 1.1 Firebase

| Question | Finding |
|---|---|
| Client configs present? | `apps/customer_app/android/app/google-services.json`, `apps/shopkeeper_app/android/app/google-services.json`, `config/firebase/google-services.json` — all **public client** configs |
| Flutter dependencies | `customer_app`: `firebase_core ^4.0.0`, `firebase_auth ^6.0.0`, `firebase_messaging ^16.0.0`. `shopkeeper_app`: `firebase_core ^4.0.0`, `firebase_auth ^6.0.0` |
| Backend SDK | `firebase-admin>=6.5.0` — used in `app/services/firebase_verification.py` and `app/services/push_service.py` |
| Service-account credential | **never a file in git** — only `FIREBASE_CREDENTIALS_FILE` / `FIREBASE_CREDENTIALS_JSON` env vars |

Firebase serves three distinct capabilities (see §2), not one.

### 1.2 Google Cloud Platform (GCP)

| Question | Finding |
|---|---|
| `google-cloud-*` SDKs? | **None** in `backend/requirements.txt` |
| Terraform / gcloud / service accounts? | **No GCP Terraform.** No GCP service-account keys (`.gitignore` blocks `*gcp*.json`) |
| What GCP *is* used for | Only Google-hosted **APIs** consumed over HTTPS: Firebase platform, Google OAuth 2.0 (`GOOGLE_CLIENT_ID/SECRET`), Google Maps Platform (`GOOGLE_MAPS_API_KEY`, `GOOGLE_APPLICATION_CREDENTIALS`) |

**Conclusion:** GCP is *not* an infrastructure provider here. It is a source of
managed identity and API endpoints. No GCP compute, storage, or database exists.
This is deliberate — adding GCP compute would create a second infrastructure
plane for no benefit.

### 1.3 AWS

| Service | Evidence in repo |
|---|---|
| **EC2** (`t3.micro`, Caddy + Docker) | `deploy.sh` (Ubuntu/EC2 paths), `docs/architecture/AWS_ARCHITECTURE.md` |
| **RDS PostgreSQL 16 + PostGIS** | `docs/database/PHASE4_RDS_POSTGRESQL_POSTGIS.md`, SQLAlchemy/PostGIS models |
| **S3** | `app/services/media_service.py`, `app/api/routes/media.py`, backup monitor, CloudTrail log target |
| **Lambda** (S3-event media processor) | `backend/lambda_function.py`, `infrastructure/lambda_staging/` |
| **Secrets Manager** | `app/core/aws_secrets.py` (`USE_AWS_SECRETS`, IAM role, no static keys) |
| **SSM Parameter Store** | `deploy.sh` → `/hyperlocal/production/database_url` (with decryption) |
| **IAM** | `boto3.client("iam")`; instance-role credential chain |
| **CloudWatch** | `app/core/metrics.py`, `app/core/alerting.py`, VPC flow logs |
| **CloudTrail** | `app/core/cloudtrail.py` (logs to S3) |
| **SNS** | optional SMS provider (`SMS_PROVIDER=aws-sns`) |
| **SES** | optional email provider (`EMAIL_PROVIDER=aws-ses`) |
| **Redis** | **local Docker container on the EC2 host** — *not* ElastiCache today (`docs/architecture/AWS_ARCHITECTURE.md:105`) |

---

## 2. Capability matrix (canonical)

| Capability | Owning Provider / Service | Reason / Spec |
|---|---|---|
| Relational data | **AWS RDS — PostgreSQL 16 + PostGIS** | Spatial integrity; SQLAlchemy models + Alembic migrations |
| Geospatial queries | **PostGIS (in RDS)** | `ST_*` radius / nearest-neighbour work; Redis caches hot results |
| Object storage | **AWS S3** | Presigned direct-to-S3 upload; `STORAGE_PROVIDER=s3` enforced for staging/prod |
| Image processing / media events | **AWS Lambda** | S3 `ObjectCreated` processor advances media lifecycle state |
| Cache + Celery broker/result | **Redis (Docker on EC2)** | `REDIS_URL`, `CELERY_BROKER_URL`; ElastiCache is the documented Stage-B upgrade |
| Background jobs | **Celery on EC2** | `app/core/celery_app.py`; beat schedules |
| Compute (API) | **AWS EC2 t3.micro** | Caddy reverse proxy + Docker; ECS Fargate is the Stage-B upgrade |
| Configuration secrets | **AWS Secrets Manager** | `USE_AWS_SECRETS=true` → entrypoint hydrates env; IAM role, zero static keys |
| Non-secret config | **AWS SSM Parameter Store** | `deploy.sh` fetches `DATABASE_URL` with `--with-decryption` |
| Audit trail (cloud) | **AWS CloudTrail → S3** | API-level record of account activity |
| Observability | **AWS CloudWatch** | Metrics, log retention, 14-day VPC flow logs |
| Transactional email | **AWS SES** (canonical) | `EMAIL_PROVIDER=aws-ses`; `smtp`/`sendgrid` are legacy alternatives (§6.3) |
| SMS (non-OTP) | **AWS SNS** (canonical) | `SMS_PROVIDER=aws-sns`; `twilio` is the legacy alternative (§6.2) |
| **Phone OTP delivery** | **Firebase Phone Auth** | SMS sent by Google; backend only *verifies* the resulting ID token |
| Push notifications | **Firebase Cloud Messaging (FCM)** | `app/services/push_service.py`; `mock` provider for dev/test |
| Federated identity (social) | **Firebase Auth** | Google Sign-In via native Credential Manager |
| Session & authorization | **FastAPI + custom role JWT** | Dual-app RBAC; Firebase identity is exchanged for a platform JWT |
| Role/permission enforcement | **FastAPI** (`app/core/permissions.py`, `ShopAccess.require`) | Single authorization engine for customer + shopkeeper + admin |
| Maps & geocoding | **Google Maps Platform** | `google_maps_flutter` client-side; optional server geocode |
| API contract | **FastAPI OpenAPI → `packages/api_contracts/openapi.json`** | Generated spec is the cross-app contract |

---

## 3. Authentication: why Firebase **and** custom JWT is not redundancy

This is the most common misreading of the stack, so it is recorded explicitly.

| Layer | Owner | Responsibility |
|---|---|---|
| Credential / identity proof | **Firebase Auth** | Proves *who the human is*: phone OTP (customer app), Google Sign-In (shopkeeper app). Backend verifies the Firebase ID token via `firebase-admin` in `app/services/firebase_verification.py` |
| Session + authorization | **Custom role JWT (FastAPI)** | Issues the platform's own access/refresh token, carries **app role** (`CUSTOMER` / `SHOPKEEPER` / `ADMIN`) and shop-scoped permissions; `TokenBlacklist` + `AuthSession` enable revocation |

These are **different jobs**. Firebase cannot express shop-scoped RBAC, and the
custom JWT cannot prove a phone number. One is an *identity provider*, the other
an *authorization/session engine*. Both stay.

Verified during discovery: `firebase_verification.py` keeps a bounded in-memory
verified-token cache (SHA-256-keyed, `exp`-evicted, max 2048) purely to avoid
blocking the event loop on Google's certificate servers — it stores **public
claims only**, never secrets.

---

## 4. Credential isolation (verified)

| Control | Status | Evidence |
|---|---|---|
| No private keys inside Flutter apps | **Pass** | Recursive search for `*.pem`, `*.key`, `*.p12`, `*.jks`, `*adminsdk*.json`, `*gcp*.json`, `serviceAccountKey*.json` across `apps/` returned **zero** files |
| Flutter ships public configs only | **Pass** | `google-services.json` holds a package-restricted public API key; `MAPS_API_KEY` / `API_BASE_URL` injected via `--dart-define` |
| Server secrets stay server-side | **Pass** | `tests/test_secrets_management_phase8.py::test_flutter_apps_carry_public_keys_only` scans app source for `JWT_SECRET`, `DATABASE_URL`, `SENDGRID_API_KEY`, `TWILIO_AUTH_TOKEN`, `GOOGLE_CLIENT_SECRET`, `FCM_CREDENTIALS`, `SMTP_PASSWORD`, `STRIPE_SECRET`, `AWS_SECRET_ACCESS_KEY`, `FAST2SMS_API_KEY` |
| Keys never committed | **Pass (local caveat)** | `.gitignore` blocks `*.pem`, `*.key`, `*.p12`, `*.jks`, `*gcp*.json`, `*firebase-adminsdk*.json`, `serviceAccountKey*.json`. `scripts/security/scan_secrets.py --tracked` reports **0 findings across 1306 tracked files**. A gitignored `hyperlocal-prod-key.pem` exists **on disk only** at the repo root (listed in the Phase 8 known-incidents allowlist) |
| AWS auth uses no static keys | **Pass** | `aws_secrets.py` uses the default credential chain (container IAM role) |
| Secret scanning in CI | **Pass** | `.gitleaks.toml` + `.github/workflows/secret-scan.yml` run gitleaks **and** `scan_secrets.py` |

### 4.1 Local-only material (do not commit)
`hyperlocal-prod-key.pem` lives at the repo root and is gitignored. It is
referenced as a known local-only incident in
`tests/test_secrets_management_phase8.py::KNOWN_LOCAL_INCIDENTS`. Rotation/prune
procedure: `docs/security/PHASE_8_SECRETS_MANAGEMENT.md`.

---

## 5. Cost visibility

Free-tier posture from `docs/deployment/COST_GUIDE.md` and
`docs/architecture/AWS_ARCHITECTURE.md`:

| Service | Free-tier allowance | Current use | Cost |
|---|---|---|---|
| EC2 t3.micro | 750 h/month | 750 h | $0 |
| EBS | 30 GB | 20 GB | $0 |
| Elastic IP | attached | 1 | $0 |
| RDS db.t3.micro | 750 h/month | 750 h | $0 |
| RDS storage | 20 GB | 20 GB | $0 |
| S3 | 5 GB + 20k GET + 2k PUT | < 5 GB | $0 |
| SSM Parameters | unlimited | < 100 | $0 |
| VPC Flow Logs | 10 GB/month | < 10 GB | $0 |
| **Total** | | | **$0/month** |

Post-free-tier estimate: **~$25/month** (EC2 ~$7.60, RDS ~$15.00, S3 ~$0.12,
CloudWatch ~$1.00).

**Budget-alert requirement:** any paid-capable service enabled beyond the table
above (ElastiCache, ECS Fargate, ALB, CloudFront, WAF, OpenSearch) **must** have
an AWS Budgets alert configured before go-live. None are enabled today, so no
alert is currently required — this is the trigger condition.

Free-tier-safe defaults that must not be silently raised:
- `AWS_REGION` / `S3_REGION` = `ap-south-1`; `AWS_SES_REGION` / `AWS_SNS_REGION` = `us-east-1`
- `S3_UPLOAD_URL_EXPIRES_SECONDS` = 600, `S3_DOWNLOAD_URL_EXPIRES_SECONDS` = 900
- Media size caps enforced by the S3 POST policy **and** re-checked at confirm
- `S3_ACL` = `private`

---

## 6. Overlap & redundancy register

Recorded, not deleted (zero-deletion rule). Each entry names the canonical owner.

### 6.1 Google OAuth vs Firebase Auth — **genuine overlap, review**
Both `app/api/routes/google_auth.py` and `app/api/routes/firebase_auth.py` are
mounted in `main.py` (~lines 188–226). Google Sign-In is therefore reachable two
ways: raw OAuth 2.0 (`GOOGLE_CLIENT_ID` / `SECRET`) and Firebase Auth's Google
provider (which is what `shopkeeper_app` actually uses).

**Canonical:** Firebase Auth — fewer moving parts, already the shopkeeper path.
**Action:** confirm the customer app does not depend on raw `google_auth` before
retiring that route. Until confirmed, both stay mounted.

### 6.2 SMS — Firebase Phone Auth supersedes the gateway config
`SMS_PROVIDER` still accepts `mock | twilio | aws-sns`, but OTP no longer uses
any of them: `firebase_verification.py` states Firebase Phone Auth "replaces
Fast2SMS for OTP delivery", and `SMS_PROVIDER` defaults to `"mock"`.
**Canonical:** Firebase Phone Auth for OTP; AWS SNS for any non-OTP SMS.
**Flag:** `twilio` is a legacy fallback with no active caller.

### 6.3 Email — four implementations, one switch
`EMAIL_PROVIDER: mock | smtp | sendgrid | aws-ses`, with `aiosmtplib`, `sendgrid`
and SES all installed.
**Canonical:** AWS SES (keeps mail on the existing AWS billing/audit plane).
**Flag:** `smtp` and `sendgrid` are legacy alternatives; do not wire new callers
to them.

### 6.4 Object storage — S3 canonical
`STORAGE_PROVIDER: local | s3 | cloudinary`. `environment_validator.py` forces
`s3` for both `staging` and `production`; `local` exists for dev.
**Canonical:** AWS S3. **Flag:** `cloudinary` is a legacy alternative.

### 6.5 Redis — local now, ElastiCache later
Redis runs as a Docker container on the EC2 host. This is correct for the current
single-instance free-tier stage (`REDIS_UNAVAILABLE_GRACE_SECONDS` exists to
degrade gracefully). **Canonical:** local Docker Redis **now**; ElastiCache on
multi-instance cutover. Not a redundancy — a staged migration.

---

## 7. Architecture decisions log

| # | Decision | Rationale |
|---|---|---|
| D1 | Relational + spatial data lives only in RDS/PostgreSQL + PostGIS | One query engine for radius search and OLTP; avoids a second datastore |
| D2 | Uploads are presigned direct-to-S3, never proxied through FastAPI | No large bodies on app servers; size/type enforced by the S3 POST policy and re-checked at confirm |
| D3 | GCP is consumed as APIs only, never as infrastructure | Avoids a second infra plane; Firebase covers the identity + push needs |
| D4 | Firebase proves identity; the platform JWT grants authorization | Firebase cannot express shop-scoped RBAC (§3) |
| D5 | All runtime secrets come from Secrets Manager via IAM role | No static keys in source, images, or git |
| D6 | Media side-effects run in Lambda on S3 events | Keeps slow processing off the request path |
| D7 | `packages/api_contracts/openapi.json` is generated from FastAPI | Prevents hand-maintained client contracts from drifting |

---

## 8. Maintenance rules

1. **Before adding a service**, read §2. If the capability already has an owner,
   extend that owner instead.
2. **Update §2 and §7 in the same commit** as any change to provider usage.
3. **Re-run discovery** whenever a `pubspec.yaml`, `requirements.txt`,
   `google-services.json`, or `infrastructure/` change lands.
4. **Never** place a private key, service-account JSON, or server secret in a
   Flutter app, an image layer, or a tracked file. Client configs are public keys only.
5. **Adding a paid-capable service** requires a budget alert first (§5).
6. **Retiring a provider** moves it to §6 as legacy; removal requires an explicit
   decision recorded here — never a drive-by deletion.
=======
# Cloud Ownership & Capability Matrix

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
>>>>>>> df52917a7cb5682bf046490fca274c80b8bb3b91
