# PHASE 23 — SECURITY AUDIT

Production security audit of the Hyperlocal platform (backend, infrastructure,
CI/CD, and deployment topology). Every checklist area was reviewed, automated
checks were run, and all critical/high findings found were fixed before release.

---

## 1. Executive summary

**Result: PASS after remediation.** The codebase already had a strong security
posture (parameterized SQL, JWT claims + refresh rotation + blacklist, salted
HMAC OTP storage, upload magic-byte validation, HSTS/security headers, secret
management via IAM + Secrets Manager, fail-fast production startup gate). The
audit found **3 critical**, **4 high**, and several medium/low issues. All
critical and high items were fixed in this phase.

Outside-of-repo actions still required by the operator are called out in §4
(rotate the Firebase service account + any matching AWS CLI keys, since a
credential-bearing checkpoint commit exists in local git object history).

---

## 2. Automated checks run

| # | Tool | Scope | Result |
|---|------|-------|--------|
| 1 | `scripts/security/scan_secrets.py --tracked` | all 754 git-tracked files | ✅ **CLEAN** — 0 findings |
| 2 | `scripts/security/scan_secrets.py --history` | full git history blobs | ⚠️ flags 2 blobs — see §4 (commit is **not** on `main`/`origin`) |
| 3 | OSV batch query (`api.osv.dev/v1/querybatch`) | 26 pinned runtime deps | ✅ no known vulnerabilities |
| 4 | `python -m compileall app tests` | all Python source | ✅ compiles |
| 5 | pytest suites (hardening/phase30, subscription/phase28, S3/phase7, identity/access, phase20/21 E2E) | security-relevant + integration | ✅ **119 + 8 + 16 + targeted subsets all pass** |
| 6 | OpenAPI introspection (`app.openapi()`) | route-level auth presence | ✅ all previously-anonymous mutations now require auth |
| 7 | compose YAML parse | 3 compose files | ✅ valid |
---

## 3. Checklist findings → status

### IAM
**Status: ✅ PASS (no change required)**
- `infrastructure/terraform/foundation/github_oidc.tf` — GitHub Actions assumes AWS via
  OIDC (no long-lived CI keys); trust scoped with `StringLike` on
  `token.actions.githubusercontent.com:sub` to
  `repo:org/repo:ref:refs/heads/main` + `environment:production` + explicit
  allow-list (`vars.github_allowed_subjects`).
- `infrastructure/terraform/foundation/human_operator.tf` — the only long-lived
  credential is a small bootstrap user whose entire policy is "assume the
  operator role". Operator role policies are per-domain (compute/network,
  data/secrets/KMS, edge/ACM/Route53/DynamoDB-lock) and project-scoped. No
  `iam:*` or `AdministratorAccess`.
- `infrastructure/terraform/ec2.tf` — instance role is least-privilege: `ssm:Get*`
  within `/project/env/*`, S3 read/write on the uploads + backups buckets only;
  IMDSv2 **required**; `AmazonSSMManagedInstanceCore` (no SSH port exposed).
- CI/CD deploy role (foundation) — ECR push + ECS update only.

### Database exposure
**Status: ✅ PASS (no change required)**
- RDS (`infrastructure/terraform/rds.tf`): `publicly_accessible = false`, in the data
  subnet with **no** default route, security group allows **5432 from the app
  SG only**, `storage_encrypted = true`, `deletion_protection = true`,
  `backup_retention_period = 7` (PITR). Master password is `random_password`
  stored in state + SSM SecureString only — never source-controlled.

### Redis exposure
**Status: ✅ PASS (no change required)**
- No ElastiCache on the free-tier topology. Redis runs as a local Docker
  container bound to the host loopback / compose network only
  (`docker-compose.cloud.yml` `redis` — no published ports; the only host port
  published is API → `127.0.0.1`).

### S3 exposure
**Status: ✅ PASS (no change required)**
- Uploads bucket is PRIVATE (`aws_s3_bucket_public_access_block` — all four
  blocks **true**), TLS-only bucket policy (Deny on `aws:SecureTransport` =
  false), SSE (AES256) by default, lifecycle rule aborts incomplete multipart
  uploads after 7 days. Object reads go through short-lived presigned GET URLs
  after an authorization check (`S3_ACL=private`).
### Secrets
**Status: ⚠️ PASS with operator action (§4) + hardening shipped**
- Tracked-files scan: **clean** — no secrets in `main`/`origin`.
- `--history` scan flagged 2 blobs that are **not** ancestors of `main` or any
  branch/`origin/*` (only reachable via local `refs/cline/checkpoints/...`):
  a Firebase service-account JSON private key and `aws_access_key` / secret in
  `.tools/tf_init_plan.ps1`. **Please rotate the Firebase service-account
  credential and any matching AWS CLI access keys**, then optionally purge the
  local reflog/objects.
- Backend runtime secrets are injected only via env / AWS Secrets Manager
  (`app/core/aws_secrets.py`, `entrypoint.sh`). New `MOCK_PAYMENT_SECRET`
  setting added (see below). `.dockerignore` and `.gitignore` exclude
  `*firebase-adminsdk*.json`, keystores, `.env*`, etc.

### JWT
**Status: ✅ PASS (no change required — already hardened)**
- HS256 with strong secret enforced by the production startup gate
  (`app/core/startup_checks.py`: rejects known defaults and secrets < 32
  chars). Claims include `iss`, `aud`, `iat`, `exp`, `jti`, `type`
  (access/refresh separation), `session_id`. Refresh tokens are opaque
  (CSPRNG, SHA-256-hashed at rest), rotated on every refresh, with reuse
  detection that revokes the session. Blacklist + server-side session check on
  every request.

### Authentication
**Status: ✅ PASS (no change required)**
- OTP: CSPRNG 6-digit codes, **salted HMAC-SHA256 digest stored** (raw never
  persisted), constant-time compare, single-use atomic flip, 5-min expiry,
  max-attempt lockout, resend cooldown. Google OAuth: signed one-time state
  token (CSRF), ID-token profile verification, account-linking guarded,
  open-redirect protection on the SPA redirect.
- **New:** `POST /api/auth/google` and `GET /api/auth/google/callback` are
  now rate-limited (100/min default). The login-URL handler lacked a `request`
  arg required by slowapi — fixed.

### Authorization
**Status: ✅ PASS (no change required)**
- RBAC with roles/permissions + shop-association checks
  (`resolve_shop_access`), admin sub-role catalog
  (`app/core/admin_permissions.py`, e.g. `admin_support`, `admin_moderator`,
  `admin_analyst`), fine-grained `require_admin_permission(resource, action)`.
  `/shops/admin/*` inline role checks refactored to the `require_admin`
  dependency for consistency (same 403 semantics, clearer contract).

### Rate limits
**Status: ✅ PASS with critical XFF fix**
- Auth endpoints: `5/minute`; everything else: `100/minute`; Redis-backed
  counters in prod (`RATE_LIMIT_STORAGE_URI=redis://…/3`), in-memory fallback
  on outage.
- **CRITICAL FIX — proxy header trust:** uvicorn was launched with
  `--proxy-headers --forwarded-allow-ips "*"` while `TRUST_X_FORWARDED_FOR`
  is enabled and Caddy only **appended** `X-Forwarded-For`. `slowapi` keys on
  the left-most XFF value ⇒ any client could set
  `X-Forwarded-For: <victim-ip>` and bypass/poison rate limits (and abuse
  detection). Fixed by:
  - Caddy now **overwrites** `X-Forwarded-For` with `{remote_host}`
    (`infrastructure/terraform/Caddyfile.tftpl`).
  - uvicorn `--forwarded-allow-ips` pinned to `127.0.0.1,172.16.0.0/12`
    (`backend/Dockerfile`, `docker-compose.cloud.yml`).
  - The direct-to-:80 free stack no longer passes `--proxy-headers` at all.
### CORS
**Status: ✅ PASS (no change required)**
- Explicit origins (`CORS_ORIGINS`, `allow_origins=…`), `allow_credentials=True`
  only ever paired with an explicit allow-list; the startup gate refuses to
  boot in production if origins are empty or `*` while credentials are allowed.
  Mobile apps are CORS-exempt (native HTTP).

### SQL injection
**Status: ✅ PASS (no change required)**
- All queries routed through the SQLAlchemy ORM with bound parameters; no
  string-concatenated SQL anywhere in `app/` (search engine uses
  parameterized `text()` constructs with positional binds + PostGIS functions).

### Validation
**Status: ✅ PASS (no change required)**
- Pydantic v2 schemas with bounds/patterns across all routes; query params
  clamped (page≥1, limit≤200/100/50, lat/lng ranges, radii≤100km); barcode
  format (digits, ≤32 chars) validated before touching the catalog.

### File upload
**Status: ✅ PASS with improvement**
- Existing: per-category extension allow-lists, **magic-byte sniffing** for
  direct uploads (`.xlsx` `PK\x03\x04`; jpeg/png/webp/pdf), size caps for
  images (5 MB) and documents (15 MB) enforced at intent + confirm time,
  server-minted object keys + scope checks (no cross-tenant addressing),
  filename sanitization (`../`, control chars, double extensions).
- **New (API-abuse hardening):** `POST /media/direct-upload` now streams the
  body in 64 KB chunks and aborts as soon as cumulative size exceeds the
  largest per-category cap — previously `await file.read()` would buffer the
  entire body unboundedly (OOM risk on multi-GB uploads).

### API abuse
**Status: ✅ PASS with fixes**
- XFF fix (above) + rate limits. Google OAuth endpoints rate-limited. All
  previously-anonymous **write** endpoints are now authenticated (§6).
- `POST /search/v2/events` and `POST /analytics/events` remain anonymous by
  design (analytics ingestion; server-side PII scrubbing documented).

### Webhook verification
**Status: ⚠️ PASS with critical fix**
- Webhook route (`/shopkeeper/subscription/webhooks/{provider_code}`) is
  intentionally unauthenticated but **HMAC-authenticated** (raw-body
  signature via provider adapters), with a `(provider, event_id)` idempotency
  ledger and constant-time comparison.
- **CRITICAL FIX — known-default gateway secret:** the built-in
  `MockPaymentProvider` signed checkouts and webhooks with the published
  `DEFAULT_MOCK_SECRET = "mock-payment-secret"`. Anyone could forge
  "payment SUCCESS" webhooks and activate paid subscriptions for free. Now:
  - New `MOCK_PAYMENT_SECRET` setting; `MockPaymentProvider` resolves its
    secret from settings.
  - Startup security gate **refuses to boot in production** while only the
    mock provider is registered AND its secret is a known default
    (`app/core/startup_checks.py` check #9).
  - Boot scripts (`infrastructure/terraform/user_data.sh.tpl`,
    `infrastructure/terraform/free/user_data.sh.tpl`) generate a random 32-byte hex secret on
    first boot and persist it across reboots.
  - `.env.production.example` / `.env.example` document the requirement.
### Logging
**Status: ✅ PASS (no change required)**
- Structured JSON logging with request/correlation IDs from middleware;
  payloads are never logged (only paths, ids, counts); OTP code values are
  never logged (only phone + mock-mode console print which is dev-only; the
  production boot script has `OTP_DEV_MODE=false`); SQLAlchemy engine logs at
  WARNING (no cached query dumps), `DEBUG=false` in production prevents
  verbose error leakage.

### Sensitive information
**Status: ✅ PASS (no change required)**
- No provider secrets hardcoded; `.env.production.example` contains
  placeholders only; API contract docs mark auth requirements; schema
  serializers select safe fields (no password/token/hash columns returned).

### Dependency vulnerabilities
**Status: ✅ PASS (no change required)**
- OSV batch query on the pinned/locked runtime dependency set (fastapi 0.141.1,
  uvicorn 0.52.4, pydantic 2.13.4, cryptography 50.0.0, sqlalchemy 2.0.52,
  bcrypt 5.0.0, redis 8.1.0, celery 5.6.3, httpx 0.28.1, python-jose 3.5.0,
  …): **no known vulnerabilities**.
- Note: `requirements` use `>=` ranges — pin exact versions in the build
  pipeline (or add `pip-audit` to CI) to prevent future drift.

### Docker security
**Status: ✅ PASS (no change required)**
- Single-stage `python:3.14-slim`, non-root `appuser`, healthcheck via stdlib
  (no curl), `.dockerignore` excludes `.env*`, credentials, tests, docs,
  scripts. New `MOCK_PAYMENT_SECRET` arrives at runtime only (hence the startup
  gate rather than image-time enforcement).

### Network security
**Status: ✅ PASS (no change required)**
- HTTPS via Caddy auto-TLS with HTTP→HTTPS redirect, HSTS preload headers at
  both Caddy and app levels; SG opens only 80/443 to the world (no SSH — SSM
  Session Manager instead); data subnet has no internet route; S3 Gateway
  endpoint keeps S3 traffic inside the VPC; VPC Flow Logs enabled (14-day
  retention). API bound to `127.0.0.1` behind Caddy; Docker ports never
  published to `0.0.0.0`.

---

## 4. Operator action required (not fixable in code)

1. **Rotate the Firebase service-account** credential
   (`hyperlocal--discovery-firebase-adminsdk-fbsvc-3e2c39a88e.json`). Its
   private key is present in a local git object (commit `e454bb6`), even
   though that commit is **not** on `main`/`origin`. Delete the Firebase key,
   generate a new one, and put `FCM_CREDENTIALS_JSON` in Secrets Manager.
2. **Rotate any matching AWS CLI access keys** from `.tools/tf_init_plan.ps1`
   (same reasoning — likely throwaway, rotate if they still exist in IAM).
3. Optionally purge local git history:
   `git reflog expire --expire=now --all && git gc --prune=now` (destructive —
   read `git help reflog` first).
4. Set a real `MOCK_PAYMENT_SECRET` (or a real payment gateway) in production
   Secrets Manager — the gate will refuse to boot without it.
---

## 5. Files changed in this phase

```
backend/app/api/routes/catalog.py          — auth on all catalog mutations
backend/app/api/routes/inventory.py        — auth on all inventory mutations
backend/app/api/routes/search.py           — auth on index rebuild/sync
backend/app/api/routes/shops.py            — require_admin dependency for /shops/admin/*
backend/app/api/routes/media.py            — bounded streaming read for direct upload
backend/app/api/routes/google_auth.py      — rate limits (+ request arg for slowapi)
backend/app/core/config.py                 — MOCK_PAYMENT_SECRET setting
backend/app/core/startup_checks.py         — payment-provider secret gate (#9)
backend/app/services/payments/mock_provider.py — settings-driven secret
backend/Dockerfile                         — pin forwarded-allow-ips
backend/docker-compose.cloud.yml           — pin forwarded-allow-ips
backend/docker-compose.free.yml            — remove --proxy-headers (no proxy)
infrastructure/terraform/Caddyfile.tftpl            — overwrite X-Forwarded-For
infrastructure/terraform/user_data.sh.tpl           — random MOCK_PAYMENT_SECRET at boot
infrastructure/terraform/free/user_data.sh.tpl                — random MOCK_PAYMENT_SECRET at boot
backend/.env.production.example            — document MOCK_PAYMENT_SECRET
backend/.env.example                       — document MOCK_PAYMENT_SECRET
backend/tests/test_production_hardening_phase30.py — gate tests + strong default
backend/tests/test_phase20_realworld_testdata.py   — admin tokens for gated routes
backend/tests/test_phase21_shopkeeper_realworld_flow.py — admin/shopkeeper tokens
backend/tests/test_phase13_production_api.py       — fix pre-existing SyntaxError
```

## 6. Endpoints previously anonymous that now require auth

Mutation-only paths (reads stay public where appropriate):

- `POST/PUT/DELETE /api/v1/catalog/*` — categories, brands, products,
  variants, identifiers, barcodes, shop-products ⇒ **admin**
- `POST /api/v1/catalog/approvals` ⇒ **any authenticated user**
  (`submitted_by` now the real caller id, was hardcoded `1`)
- `POST /api/v1/catalog/approvals/{id}/review` ⇒ **admin**
- `GET /api/v1/catalog/products/{id}/search-document` ⇒ **authenticated**
  (it recomputes + persists the search document — not a plain read)
- `POST/PUT/DELETE /api/v1/inventory/*` — inventory, movements, adjustments,
  price, offers, freshness ⇒ **admin**
- `POST /api/v1/search/v2/index/rebuild` and `/sync` ⇒ **admin**
- `GET/POST/PUT /api/v1/shops/admin/*` ⇒ **admin** (now via dependency)

## 7. Validation summary

- `python -m compileall app tests` — clean
- `python -m pytest tests/test_production_hardening_phase30.py` — **44 passed**
- `python -m pytest tests/test_subscription_phase28.py` — **33 passed**
- `python -m pytest tests/test_s3_object_storage_phase7.py` — **42 passed**
- `python -m pytest tests/test_identity_access.py::TestSecurityTokens/TestAuthorization/TestAdminAccess/TestShopOwnership/TestSessionTracking/TestAuthRoutes` — **25 passed**
- `python -m pytest tests/test_phase20_realworld_testdata.py` — **8 passed**
- `python -m pytest tests/test_phase21_shopkeeper_realworld_flow.py` — **16 passed**
- OpenAPI route-level auth assertion script — **ALL PASSED** (30 gated routes
  require auth; public reads/webhooks remain public)
- `scripts/security/scan_secrets.py --tracked` — **CLEAN**