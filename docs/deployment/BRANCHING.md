# Branching, environments & release gates

> Canonical answer to the question **"what exactly is the difference between
> `develop` and `staging`?"** — plus every rule, gate, secret and command that
> makes the flow real in this repository.

## 1. One-line answer

```
develop = WHICH code    (a git branch — cheap, instant, no infrastructure)
staging = WHERE it runs (a deployed environment — real server, DB, TLS, data)
```

They are **two different axes**, not two options. You need both:

| | `develop` | `staging` |
|---|---|---|
| What it physically is | `refs/heads/develop` — a commit pointer | EC2 + RDS + Redis container + S3 bucket + Caddy TLS + SSM params |
| Lives in | GitHub's object store | AWS `ap-south-1` (billable, takes ~15 min to create) |
| Failure mode | merge conflict, red CI | 500s, downtime, bad migration, data loss |
| Secrets | none (only committed `.env.example` templates) | real secrets from SSM `/hyperlocal/staging/*` |
| Data | none | its own DB (seeded test data, never production data) |
| Name in code/config | branch `develop` (`github_branch = "develop"`) | terraform/runtime `environment = "staging"` (`ENVIRONMENT=staging`) |
| Configuration file | none | `backend/.env.staging` (untracked) / SSM params |
| Domain | none | `https://staging-api.hyperlocal.in` |
| Delete it? | any time, no cost | destroys real infrastructure |

**Do not confuse `develop` (branch) with `development` (runtime profile).**
`development` is what runs on a laptop at `http://localhost:8000`
(`app/core/env.py` → `VALID_ENVIRONMENTS = ("development", "test", "staging", "production")`).
`develop` is the integration **branch**; the environment it deploys to is
**staging**.

## 2. The flow this repository implements

```
 GitHub repository
   │
   ├── feature/<name>  ──┐            (Cline / developer branches — one per task)
   │                     │
   │              Pull Request → `develop`
   │                     │
   │              GitHub Actions CI  (analyze · unit · integration · build · scan)
   │                     │
   │              merge → `develop`
   │                     │
   │              CD: quality battery → deploy staging (auto)
   │                     │
   │              smoke test + E2E contract battery  ← the release gate
   │                     │
   │              Pull Request → `main`  (final review, SHA already staging-proven)
   │                     │
   │              GitHub Actions CD on `main`
   │                     │
   │              quality battery → staging → smoke → E2E
   │                     │
   │              production approval (required reviewer, `production` env)
   │                     │
   │              deploy production → verify health (+ E2E) → auto rollback
   │                     ▼
   │              Docker → ECR → AWS SSM Run Command → EC2
   │                          ├── FastAPI (uvicorn, 127.0.0.1:8000)
   │                          ├── Celery worker + beat
   │                          ├── Redis (local container)
   │                          └── RDS PostgreSQL + PostGIS   ·  S3 (uploads)
```

Nothing else deploys: feature branches only open PRs, and the deploy jobs
refuse to run on any branch other than `develop` / `main`.

## 3. Gate matrix (what runs where)

| Trigger | Workflow | Gate | Deploys? |
|---|---|---|---|
| PR → `develop` or `main` | `backend-ci.yml` | reusable battery: static analysis, unit, integration (PostGIS+Redis), build, gitleaks/pip-audit, migration rehearsal + safety verdict | no |
| PR → `develop` or `main` | `flutter-customer.yml`, `flutter-shopkeeper.yml` | `analyze` + `flutter test` | no |
| push → `develop` | `backend-cd.yml` (or `backend-deploy.yml` when `DEPLOY_TARGET=ecs`) | battery → **staging** → smoke → **E2E contract** | staging only |
| push → `develop` | Flutter workflows | analyze/test + **staging APK** (`APP_ENV=staging`) | artifact only |
| push → `main` | `backend-cd.yml` / `backend-deploy.yml` | battery → staging → smoke → E2E → **approval** → production → verify → rollback on failure | staging + production |
| push → `main` | Flutter workflows | analyze/test + **production APK** (`APP_ENV=production`) | artifact only |
| PR (any branch) / weekly | `secret-scan.yml` | gitleaks + local secret scanner | no |

Hard rules encoded in the YAML:

1. **Staging is a real gate.** `deploy-production` has
   `needs: [check, migration-gate, deploy-staging, smoke-test-staging, e2e-staging]`
   plus `!cancelled() && !failure()`. If staging fails, production cannot be
   approved past it. (A *skipped* staging job — staging disabled on purpose —
   does not block a release.)
2. **Production only from `main`.** `github.ref == 'refs/heads/main'`.
3. **One deploy at a time.** Job-level concurrency groups
   `backend-staging-deploy` / `backend-production-release`; workflow-level
   `backend-cd-${{ github.ref }}`.
4. **Dangerous migrations never auto-apply** — the migration gate blocks the
   deploy unless a human re-runs with `migrate_approved=true`.
5. **Rollback is automatic** on any failure (`cicd_rollback.sh` + the server's
   own `deploy_backend.sh` self-rollback to `LAST_GOOD_SHA`).

## 4. Branch rules (protection)

Apply with `scripts/setup_branch_protection.ps1` (needs a GitHub PAT with
`repo`/`administration` scope) or manually in
**Settings → Branches → Add branch protection rule**.

`develop`:

* Require a pull request before merging (≥1 approval, stale reviews dismissed).
* Require status checks to pass — the job names below.
* Require branches to be up to date before merging.
* Require conversation resolution; disallow force pushes and deletions.

`main`:

* Everything above, plus a second reviewer if the team has the people,
  "Restrict who can push", and no bypass for the develop → main PR.

Required status checks (job `name:` values — keep those names stable):

| Workflow | Check name |
|---|---|
| `backend-ci.yml` | `Backend quality gates (static, unit, integration, build, security, migrations)` |
Required status checks — pull requests are gated by `platform-ci.yml`, so these
are the names to require (job `name:` values; keep them stable):

| Workflow | Required check |
|---|---|
| `platform-ci.yml` | `Backend quality gates`, `Customer app checks`, `Shopkeeper app checks`, `Admin panel checks`, `Shared Dart package checks` |
| `backend-ci.yml` | `Backend quality gates (static, unit, integration, build, security, migrations)` — optional extra backend gate on backend PRs |

`scripts/setup_branch_protection.ps1` applies exactly these contexts; run it with
`-Discover` to use the names GitHub actually reports for the branch (recommended
after the first CI run) or `-Checks @("...")` to set them explicitly. Deployment
jobs are intentionally **not** required checks: they run on push, not on PRs, and
branch protection only matches checks reported on the PR head.

## 5. Branch → environment mapping (single source of truth)

| Branch | Who deploys it | Environment | `ENVIRONMENT` | Domain | SSM path | Terraform preset |
|---|---|---|---|---|---|---|
| `feature/*` | nobody | — | — | — | — | — |
| `develop` | CD automatically on push | staging | `staging` | `https://staging-api.hyperlocal.in` | `/hyperlocal/staging/*` | `terraform.tfvars.staging.example` (`github_branch = "develop"`) |
| `main` | CD after human approval | production | `production` | `https://api.hyperlocal.in` | `/hyperlocal/production/*` | `terraform.tfvars.production.example` (`github_branch = "main"`) |

Environment separation is pure configuration:
`infrastructure/terraform/main.tf` → `name_prefix = "${project_name}-${environment}"`,
so every resource (VPC, EC2 tag `hyperlocal-staging-app` /
`hyperlocal-production-app`, RDS, S3, SSM parameters) differs per environment
while the code, image and compose file stay identical.

Runtime profiles and files:

| Profile | File | Notes |
|---|---|---|
| development | `backend/.env.development` | local Docker PostGIS + Redis, `DEBUG=true`, local storage |
| test | `backend/.env.test` | used by pytest |
| staging | `backend/.env.staging` (untracked) | on staging EC2 the boot script writes `.env` from SSM; `DEBUG=false`, `LOG_LEVEL=INFO`, `STORAGE_PROVIDER=s3` |
| production | `backend/.env.production.example` | same shape, production bucket/DB |

The apps pick their endpoint at build time
(`apps/*/lib/core/.../env_config.dart`): `--dart-define=APP_ENV=staging`
→ `https://staging-api.hyperlocal.in`, `APP_ENV=production`
→ `https://api.hyperlocal.in`. Staging/production builds refuse plain HTTP.

## 6. Configuration the pipeline needs

Repository **variables** (Settings → Secrets and variables → Actions → Variables):

| Variable | Used by | Example |
|---|---|---|
| `STAGING_DEPLOY_ENABLED` | enables the staging deploy jobs | `true` |
| `STAGING_API_URL` | smoke test + E2E contract battery | `https://staging-api.hyperlocal.in` |
| `STAGING_INSTANCE_TAG` | SSM Run Command target | `hyperlocal-staging-app` |
| `PROD_DEPLOY_ENABLED` | `false` disables production deploys | `true` |
| `PROD_API_URL` | verify + E2E on production | `https://api.hyperlocal.in` |
| `PROD_INSTANCE_TAG` | SSM Run Command target | `hyperlocal-production-app` |
| `CUSTOMER_STAGING_API_BASE_URL` | customer staging APK (optional override) | `https://staging-api.hyperlocal.in` |
| `SHOPKEEPER_STAGING_API_BASE_URL` | shopkeeper staging APK (optional override) | `https://staging-api.hyperlocal.in` |
| `DEPLOY_TARGET` | `compose` (EC2, default) or `ecs` (Fargate) | `compose` |
| `ECR_ENABLED`, `ECR_REPOSITORY`, `AWS_REGION`, `ECS_CLUSTER_NAME` | image push / ECS driver | `true`, `hyperlocal-backend`, `ap-south-1` |

Secrets: `AWS_DEPLOY_ROLE_ARN`, `ECR_REGISTRY_URL`, `CUSTOMER_API_BASE_URL`,
`SHOPKEEPER_API_BASE_URL`, `GOOGLE_MAPS_API_KEY`.

Protected **environments** (Settings → Environments):

* `staging` — no manual gate (fast feedback). Optionally add a wait timer.
* `production` — **Required reviewers ON**. This is the human gate before the
  approved SHA rolls onto the production instance.

## 7. Runbooks

### Everyday feature work

```powershell
git switch develop
git pull
git switch -c feature/nearby-filters

# ... work ...
powershell -ExecutionPolicy Bypass -File scripts/dev/test.ps1   # local battery

git push -u origin feature/nearby-filters
# open a PR into `develop` → backend CI + Flutter gates must be green → merge
# merging to develop triggers: battery → deploy staging → smoke → E2E contract
# download the staging APK artifact ("customer-app-staging") to QA it on device
```

### Release to production

```powershell
git switch main
git pull
git switch -c release/2026-09-22 && git merge --ff-only develop
git push -u origin release/2026-09-22     # PR into main → CI gates must be green
# merge the PR → CD runs: battery → staging → smoke → E2E → waits for approval
# Actions → Review deployments → approve: the staging-proven SHA rolls onto
# production, then verify-production runs the health check + E2E contract battery
```

### Hotfix (production is broken)

```powershell
git switch -c hotfix/<issue> main
# minimal fix + a regression test
# PR into `main` — it still goes through staging + smoke + E2E before approval
# then back-merge so develop never regresses:
git switch develop && git merge --no-ff hotfix/<issue> && git push
```

### Rolling back

* Automatic: any failed deploy/verify triggers `rollback-production`
  (ECS re-images the last good tag; compose resets to `LAST_GOOD_SHA`).
* Manual: re-run **Backend CD** via `workflow_dispatch` for the previous SHA, or
  on the box run `/opt/hyperlocal/infrastructure/scripts/deploy_backend.sh rollback`.
* Schema/data: `infrastructure/scripts/rds_migrate_rollback.sh --steps 1`, then
  `restore_db.sh` for data (see `docs/deployment/DISASTER_RECOVERY.md`).

### Running the gates locally before pushing

```powershell
# backend battery (static, unit, integration, build, security, migrations)
powershell -ExecutionPolicy Bypass -File scripts/dev/test.ps1

# E2E contract battery against a deployed environment (no credentials needed)
python infrastructure/scripts/cicd_contract_check.py `
  --url https://staging-api.hyperlocal.in --expect-env staging
```

## 8. Why this split matters (and what goes wrong without it)

* **`develop` cannot catch runtime reality.** A green unit/integration suite
  never proves that RDS is reachable from the VPC, that Caddy issued a
  certificate, that the migration actually ran, or that the deployed API still
  serves the committed contract. Staging proves exactly that.
* **`staging` cannot integrate work.** It only ever holds one SHA at a time, so
  it is the wrong place to merge features.
* **The staging gate is what makes approval meaningful.** A reviewer approves a
  SHA that already passed a real migration, real Redis, real TLS, the smoke
  battery and the E2E contract battery. Without the gate, "approve" just means
  "betting on CI".
* **Without a `develop` branch, `main` absorbs the risk.** Every experiment would
  either wait in a PR forever or land on `main` and instantly become the
  production candidate.

### Troubleshooting

| Symptom | Likely cause |
|---|---|
| `deploy-staging` skipped | `STAGING_DEPLOY_ENABLED != true`, or the push was not to `develop`/`main` |
| `deploy-production` skipped | not on `main`, `PROD_DEPLOY_ENABLED == false`, or an upstream staging job failed (by design) |
| E2E: "MISSING documented endpoints" | the deployed image is older than `packages/api_contracts/openapi.json` (contract changed without deploying, or hand-edited) |
| E2E: "undocumented endpoints" | endpoints added without running `python backend/scripts/export_openapi.py` |
| E2E: "deployment.commit is unknown" | the container has no git metadata — the smoke test's `--ssm-instance-tag` check still verifies the on-host SHA |
| Staging APK cannot reach the API | terraform `domain_name` ≠ `STAGING_API_URL` ≠ the app's staging default (`staging-api.hyperlocal.in`) |
