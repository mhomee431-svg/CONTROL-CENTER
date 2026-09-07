# PHASE 8 — SECRETS MANAGEMENT

Status: **Implemented & verified** (this phase) · Rotation of two legacy
local-only credentials: **pending user action** (see §7).

---

## 1. Architecture — where every secret lives

| Category | Secret(s) | Storage | Delivery path |
|---|---|---|---|
| Database | `DATABASE_URL` (RDS password) | **AWS Secrets Manager** `hyperlocal/<env>/database` | `rds.tf` auto-injects into the backend secret bundle; never hand-pasted |
| Auth | `JWT_SECRET_KEY` | Secrets Manager (backend JSON bundle) | ECS task + entrypoint hydration |
| OTP / SMS | `FAST2SMS_API_KEY`, `SMS_PROVIDER_*`, Twilio tokens | Secrets Manager | entrypoint hydration (`USE_AWS_SECRETS=true`) |
| Email | `SENDGRID_API_KEY`, `SMTP_PASSWORD`, SES IAM role | Secrets Manager / **IAM role** (SES) | entrypoint hydration / default credential chain |
| Push | FCM service-account JSON (`FCM_CREDENTIALS_JSON`) | Secrets Manager | entrypoint hydration |
| Payments | Gateway keys + webhook secrets | Secrets Manager | entrypoint hydration |
| AWS plumbing | — | **No static keys** — IAM task role (default credential chain) | — |
| Maps (public) | `MAPS_API_KEY` | **GitHub Actions secret** → `--dart-define` | build-time, client-restricted key |
| API base URLs | `API_BASE_URL`, `SHOPKEEPER_API_BASE_URL` | GitHub Actions variables/secrets → `--dart-define` | build-time, non-secret |

### Backend loading order (`backend/entrypoint.sh`)

1. `USE_AWS_SECRETS=true` → `python -m app.core.aws_secrets --export` fetches the
   Secrets Manager JSON bundle (KMS-decrypted via the container IAM role) and
   `eval`s shell-quoted `export KEY='value'` lines **before** any app import.
   Values are never printed or logged.
2. ECS-injected env vars always win over the bundle (hydration only fills gaps).
3. `app/core/config.py` (pydantic-settings) reads the resulting environment.
4. `app/core/startup_checks.py` **fails fast in production** on: default/short
   JWT secret, OTP dev backdoor, debug flags, wildcard CORS, mock providers.

### Public vs private keys

* **Private/server secrets** — only ever in Secrets Manager / ECS env. Never in
  git, Docker images, logs, API responses, or Flutter.
* **Public client keys** — `MAPS_API_KEY` (restricted by app package +
  API scope) and API base URLs are the ONLY values baked into Flutter builds,
  via `--dart-define` in CI (`flutter-customer.yml` / `flutter-shopkeeper.yml`).

---

## 2. Guarantee 1 — secrets are not committed

* `.gitignore`: `.env`, `.env.*`, `*.log`, tfvars/states, Firebase service
  accounts (`*firebase-adminsdk*.json`, `serviceAccountKey*.json`), and (new in
  this phase) Flutter signing material (`key.properties`, `*.jks`, `*.keystore`,
  `*.p12`, `*.mobileprovision`).
* Verified: `git ls-files` contains **no** `.env` files (only placeholder
  `*.example` references); historical `.env` commits (removed in `9fb9793`)
  held **only dev placeholders** (`dev-secret-key-change-in-production`,
  `CHANGE_ME@db.example.com`, localhost DBs).
* Regression tests: `test_tracked_tree_is_clean`, `test_no_env_files_are_tracked`.

## 3. Guarantee 2 — secrets are not logged

* `app/core/aws_secrets.py` logs **key names only**; `--export` output goes to
  the entrypoint shell (`eval`), never stdout/logs, and is `shlex.quote`d.
* `entrypoint.sh` never echoes the secret payload.
* Tests: `test_aws_secrets_hydration_never_logs_values`,
  `test_export_output_is_shell_quoted`, `test_entrypoint_never_echoes_secret_payload`.

## 4. Guarantee 3 — secrets are not embedded in Docker images

* `backend/Dockerfile` is multi-stage, non-root, and reads all secrets from the
  runtime environment — nothing baked in.
* `.dockerignore` now excludes `**/.env`, `**/.env.*`, and (new in this phase)
  all credential material: `**/*firebase-adminsdk*.json`,
  `**/serviceAccountKey*.json`, `**/*.pem`, `**/*.key`, `**/*.jks`,
  `**/*.keystore`, `**/*.p12`, `**/*.mobileprovision`.
* **Fixed this phase:** the on-disk Firebase service-account JSON would
  previously have been `COPY . .`'d into the production image.
* Test: `test_dockerignore_excludes_credentials_and_env`.

## 5. Guarantee 4 — secrets are not exposed through API responses

* POS integration credentials are stored encrypted-at-rest and serialized only
  through `POSCredentials.masked_view()` (`mock-****25` style), never raw.
* No route serializes `settings`; docs are disabled in production.
* Test: `test_pos_credentials_are_masked_never_raw` (+ phase-25 suite).

## 6. Guarantee 5 — secrets are not shipped in Flutter

* Both apps consume only `--dart-define` values (`API_BASE_URL`,
  `MAPS_API_KEY`); `apps/customer_app/.env` holds a non-secret base URL only.
* Forbidden server-side identifiers (`JWT_SECRET`, `DATABASE_URL`,
  `SENDGRID_API_KEY`, `TWILIO_AUTH_TOKEN`, `GOOGLE_CLIENT_SECRET`,
  `FCM_CREDENTIALS`, `SMTP_PASSWORD`, `STRIPE_SECRET`,
  `AWS_SECRET_ACCESS_KEY`, `FAST2SMS_API_KEY`) are asserted absent from all
  client code/config: `test_flutter_apps_carry_public_keys_only`.

---

## 7. Secret scanning

### Tooling

* **Gitleaks** (default rule set) via `.github/workflows/secret-scan.yml` on
  every push/PR + weekly full-history cron. Config: `.gitleaks.toml`.
* **Repo scanner** `scripts/security/scan_secrets.py` (dependency-free):

  ```bash
  python scripts/security/scan_secrets.py --tracked            # what would be pushed
  python scripts/security/scan_secrets.py --history            # every line ever added
  python scripts/security/scan_secrets.py --tracked --history  # CI runs both
  python scripts/security/scan_secrets.py --json --paths DIR   # ad-hoc / tests
  ```

  Detectors: AWS keys, private-key blocks, Google/Firebase keys, GCP service
  accounts, SendGrid, Stripe, Slack, GitHub, npm, credential-bearing DB/queue
  URLs, generic high-entropy `*_SECRET/*_PASSWORD/*_API_KEY/…` assignments.
  Output is always **redacted**; exit 1 on findings.

### Results (this phase)

| Scan | Result |
|---|---|
| Tracked files (731) | ✅ **0 findings** |
| History — pushed commits (`origin/main`) | ✅ **0 findings** (removed `.env*` held dev placeholders only) |
| History — **local-only** Cline checkpoint refs | ⚠️ **8 findings, 2 incidents** (below) |

### ⚠️ Known incidents (local-only, never pushed)

Both exist solely in `refs/cline/checkpoints/*` snapshot commits — verified
with `git branch -r --contains` (nothing on `origin/main`):

1. **Firebase service-account key** `backend/hyperlocal--discovery-firebase-adminsdk-fbsvc-3e2c39a88e.json`
   — still on disk (now git- & docker-ignored).
2. **AWS access key + secret** in a since-deleted `.tools/tf_init_plan.ps1`.

**Runbook (owner action):**

```bash
# 1. Rotate (do these regardless — the values sat in plaintext on disk):
#    - Firebase console → Service accounts → delete the key, mint a new one,
#      store it in Secrets Manager as FCM_CREDENTIALS_JSON.
#    - AWS IAM → deactivate/delete the affected access key, mint a new one
#      into SSM/Secrets Manager if still needed.

# 2. Purge the local checkpoint snapshots holding the old values:
git for-each-ref --format='%(refname)' refs/cline/checkpoints |
  while read -r ref; do git update-ref -d "$ref"; done
git reflog expire --expire=now --all && git gc --prune=now --aggressive

# 3. Re-scan — must be CLEAN:
python scripts/security/scan_secrets.py --tracked --history
```

Until pruned, the scanner intentionally reports these so they cannot be
forgotten; `test_git_history_has_no_untracked_leaks` fails on **any other**
historical finding.

---

## 8. Verification summary

```
backend/tests/test_secrets_management_phase8.py     → 12 passed
backend/tests/test_production_hardening_phase30.py  → 43 passed (regression)
gitleaks: .gitleaks.toml + .github/workflows/secret-scan.yml (push/PR/weekly)
```


