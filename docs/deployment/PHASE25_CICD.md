# PHASE 25 - Automated CI/CD

**Status:** Implemented - 2026-09
**Scope:** A staged release pipeline for the backend. Every code change is run
through the full quality battery, then deployed to staging, smoke-tested,
approved by a human, deployed to production, health-verified, and rolled back
automatically on any failure. Dangerous database migrations are never
auto-applied without explicit approval.

## 1. Architecture

A push or merge to main (or a manual dispatch) triggers:

1. **`reusable-backend-checks.yml`** - the quality gate (steps 1-8):
   checkout, install dependencies, static analysis, unit tests, integration
   tests (PostGIS + Redis), build, security scan, migration rehearsal.
2. **`backend-cd.yml`** (default driver, EC2 + Docker Compose) - steps 9-14:
   deploy staging, smoke test, then after production approval deploy
   production, verify health, and roll back automatically on failure.
3. **`backend-deploy.yml`** (ECS / Fargate driver, active when the repo
   variable `DEPLOY_TARGET=ecs`) - the same staged rollout using service
   images instead of an instance checkout.

Exactly ONE driver deploys per push. The variable DEPLOY_TARGET (unset =>
compose) selects it; the other pipeline's deploy jobs are skipped.
All steps use GitHub OIDC to assume the scoped `hyperlocal-cicd-deploy` role
(no long-lived AWS keys).

## 2. The 14 required steps and where they run

| # | Required step             | Job / script                                         |
|---|---------------------------|------------------------------------------------------|
| 1 | Checkout                  | every job: `actions/checkout@v4`                     |
| 2 | Install dependencies      | setup-python + `pip install -r requirements.txt`     |
| 3 | Static analysis           | `static-analysis`: compileall, ruff (E9/F811/F821/F822/F823), bandit baseline |
| 4 | Unit tests                | `unit-tests`: pytest without services                |
| 5 | Integration tests         | `integration-tests`: PostGIS+Redis containers, alembic upgrade head, verify_rds, recovery drill, full pytest |
| 6 | Build                     | `build`: docker build backend/Dockerfile             |
| 7 | Security scan             | `security-scan`: gitleaks, pip-audit, local scanner  |
| 8 | Artifact / image          | `push-image`: ECR tags plus `:sha` / compose git SHA |
| 9 | Deploy staging            | `deploy-staging` (env `staging`): SSM Run Command    |
|10 | Smoke test                | `smoke-test-staging`: /health /ready /openapi + SHA  |
|11 | Production approval       | `environment: production` (required reviewers)      |
|12 | Deploy production         | `deploy-production`                                 |
|13 | Verify health             | `verify-production` against PROD_API_URL             |
|14 | Roll back automatically   | `rollback-*` jobs on `failure()` + server-side self-rollback |

## 3. Environments and approvals

The protected environments are configured in
`Settings > Environments`:

- `staging`: the staging deploy/smoke jobs bounce; no manual gate so the
  pipeline gives fast feedback.
- `production`: `Required reviewers` is ON. The `deploy-production` job
  waits for approval before it rolls the image onto the production
  instance. `rollback-production` uses the same environment.

Only the production environment can release to production, and only after a
human approves the exact SHA that already passed staging.

## 4. Migration safety (never auto-deploy dangerous migrations)

Migrations can damage data, so the pipeline gates them four ways:

1. Static scrutiny: `backend/scripts/migration_safety_check.py` AST-scans the
   migration files changed by this push for drop operations (DROP TABLE /
   COLUMN / INDEX / CONSTRAINT), TRUNCATE, DELETE FROM, batch drops and raw
   destructive DDL. It produces `backend/migration_safety_report.json`.
2. Approval gate: the deploy workflows read the scan verdict. If it reports
   DANGEROUS, the pipeline refuses to apply migrations unless the operator
   explicitly re-runs with `migrate_approved=true` (workflow dispatch input,
   manual review required).
3. Rehearsal: the `integration-tests` job applies `alembic upgrade head` to a
   throwaway PostGIS database and runs the recovery drill on every single run,
   before any environment is touched.
4. Safe application with snapshot: on the instance, `cicd_migrate.sh` takes a
   schema-only `pg_dump` before applying (uploaded to the backups bucket when
   SNAPSHOT_BUCKET is set), then runs `alembic upgrade head`, then the app
   only starts. RDS automated backups / PITR stay as the Phase 5 safety net.

## 5. Rollback strategy

Three layers, applied automatically in this order:

| Layer | Scope | Mechanism |
|------|-------|-----------|
| L1 App | compose | `deploy_backend.sh rollback` returns checkout + stack to LAST_GOOD_SHA (SSM-driven). ECS: re-image the previous good tag. |
| L1B self-heal | compose | `deploy_backend.sh` already rolls back on a failed /ready during deploy - the CI/CD rollback is a second net. |
| L2 schema | DB | `infrastructure/scripts/rds_migrate_rollback.sh --steps 1` (Alembic downgrade, guarded, data preserved). |
| L3 data | DB | `restore_db.sh` / `rds_restore.sh` from the Phase 5 backups / snapshots. |

`cicd_rollback.sh` orchestrates L1 from the pipeline (compose and ECS); layers
L2 and L3 are documented and available for exactly the dangerous-migration
scenario that human approval is designed to catch.

## 6. Repository variables / secrets (Settings > Secrets and variables)

Secrets:
- AWS_DEPLOY_ROLE_ARN - the scoped ci_deploy role (existing).
- ECR_REGISTRY_URL - ECR endpoint (needed for the push-image job / ECS).

Variables (with defaults - overridable):
- AWS_REGION (ap-south-1), DEPLOY_TARGET (compose|ecs), ECR_REPOSITORY is
  `hyperlocal-backend`, ECR_ENABLED, STAGING_DEPLOY_ENABLED, STAGING_API_URL,
  STAGING_INSTANCE_TAG (hyperlocal-staging-app), PROD_API_URL,
  PROD_INSTANCE_TAG (hyperlocal-production-app), WEB_SERVICE/WORKER_SERVICE/
  BEAT_SERVICE + STAGING_* for ECS, ECS_CLUSTER_NAME, PREVIOUS_IMAGE.

The workflow reads them via the GitHub `vars` context; see the file
`.github/workflows/backend-cd.yml` for every usage with its fallback value.

## 7. IAM additions (infrastructure/terraform/foundation/cicd_runtime.tf)

The `ci_deploy` role grows `ssm:SendCommand`/`GetCommandInvocation`, EC2
describe (for the Name-tag lookup), and optional S3 bucket access for output
pinning. `locals.tf` also adds `environment:staging` to the OIDC allowlist so
the staging-env jobs can assume the role. Apply stage foundation (or run
`terraform apply -target=aws_iam_role_policy.ci_deploy_runtime`) before first
staging use.

## 8. Notes for operators

- Protect `production` environment reviewers BEFORE enabling the pipeline.
- First runs: the static-analysis, unit & integration tests must pass;
  nothing deploys until they do.
- The compose deploy reuses the server's existing `deploy_backend.sh` and
  records LAST_GOOD_SHA, so a failed deploy never leaves production running
  the new, unreviewed commit.
- Keep `bandit_baseline.json` current after adding code: regenerate with
  `python -m bandit -q -r app -ll -f json -o bandit_baseline.json`.
- The `migration_safety_report.json` from every run is attached as an artifact
  for the audit trail.

