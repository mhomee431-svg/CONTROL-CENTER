---
title: Development, Staging and Production Workflow
last_reviewed: 2026-10-08
---

# Development, Staging and Production Workflow

This document describes the checks and AWS deployment path for this
repository. A successful build does not replace verifying the deployed
application, database backups, and operational alerts.

## Pipeline

```
push / pull request
    |
    +-- frontend: typecheck -> lint -> tests -> production build
    +-- backend: Python 3.12 tests
    +-- infrastructure: CDK typecheck -> synth -> both container builds
    +-- security: shipped dependency audit
    +-- security workflow: npm audit and CodeQL
            |
            +-- AWS deployments require explicit repository-variable opt-in
```

CI runs on Node 24 and Python 3.12. Production deploys use the same commit
that passed CI. Configure GitHub's `production` environment with required
reviewers to require approval before the production job assumes its AWS role.

**Development mode:** CI checks run on pushes and pull requests, but AWS
deployments are disabled unless the repository variable
`ENABLE_AWS_DEPLOYMENTS` is explicitly set to `true`. Leave it unset while
building features; AWS credentials and domain variables alone cannot trigger
a deployment.

## AWS architecture

The CDK application in `infrastructure/` provisions an internet-facing
Application Load Balancer, an ECS Fargate service for the Next.js standalone
server, a separate FastAPI service, and a private RDS PostgreSQL instance.
The ALB redirects HTTP to HTTPS and sends `/api/v1/*` and `/health` to the API;
all other paths go to Next.js. The API and web tasks are not publicly
addressable. The database accepts connections only from the API task security
group. Container logs are retained in CloudWatch Logs, the API signing key and
database credentials are held in Secrets Manager, and production enables
multi-AZ ECS/RDS and deletion protection.

The stack uses billable AWS resources (including NAT gateways, an ALB, ECS
tasks, and RDS). Configure AWS Budgets and review the selected region's prices
before enabling automatic deployment. The stack does not create a domain,
ACM certificate, AWS account, OIDC provider, or GitHub environment.

The shipped frontend dependency gate (`npm audit --omit=dev --audit-level=high`)
passes. Full audit reports still show high findings in development-only
frontend lint dependencies and in AWS CDK's bundled `brace-expansion` 5.0.9.
The current latest `aws-cdk-lib` bundles that version, so npm cannot repair it
with a lockfile-only update; the infrastructure audit is recorded as an
artifact and should be rechecked when CDK releases a patched bundle.

## One-time AWS and GitHub setup

1. Choose an AWS account and region. In that region, request and DNS-validate
   ACM certificates covering the staging and production hostnames. The ALB
   certificate must be in the same region as the ALB.
2. If the domain is hosted in Route 53, note its hosted-zone ID and zone name.
   Otherwise, leave the hosted-zone variables empty and create DNS alias/CNAME
   records pointing to the ALB DNS name printed by the stack.
3. Configure GitHub Actions OIDC in the AWS account. Create an IAM OIDC
   provider for `https://token.actions.githubusercontent.com`; trust only this
   repository and the intended refs/environments. The staging job's subject
   is `repo:mhomee431-svg/CONTROL-CENTER:ref:refs/heads/main`; production uses
   `repo:mhomee431-svg/CONTROL-CENTER:environment:production`. The deploy role
   must be allowed to assume the CDK bootstrap deployment/publishing roles
   and pass the task roles. Bootstrap CDK once per account/region using an
   organization-approved CloudFormation execution policy. Do not store AWS
   access keys in GitHub.
4. Add these **repository variables** under Settings -> Secrets and variables
   -> Actions:

   | Variable | Required | Purpose |
   | --- | --- | --- |
   | `AWS_ROLE_ARN` | yes | OIDC role ARN for the CDK deployment |
   | `AWS_REGION` | yes | AWS region used by the stacks |
   | `AWS_STAGING_DOMAIN_NAME` | yes | Full staging hostname |
   | `AWS_STAGING_CERTIFICATE_ARN` | yes | ACM certificate ARN for staging |
   | `AWS_STAGING_HOSTED_ZONE_ID` | no | Route 53 zone ID when using Route 53 |
   | `AWS_STAGING_HOSTED_ZONE_NAME` | no | Zone name paired with the zone ID |
   | `AWS_PRODUCTION_DOMAIN_NAME` | yes | Full production hostname |
   | `AWS_PRODUCTION_CERTIFICATE_ARN` | yes | ACM certificate ARN for production |
   | `AWS_PRODUCTION_HOSTED_ZONE_ID` | no | Route 53 zone ID when using Route 53 |
   | `AWS_PRODUCTION_HOSTED_ZONE_NAME` | no | Zone name paired with the zone ID |

   Keep each hosted-zone ID/name pair either fully populated or both empty.
   Use distinct staging and production domain/certificate values.
5. Create a GitHub environment named `production`, add required reviewers, and
   restrict deployment branches/tags to the release policy. Enable branch
   protection on `main` and require the `typecheck, lint, test, build`,
   `backend tests`, `AWS infrastructure synthesis`, and
   `production dependency audit` checks.
6. Only when you intentionally want AWS staging deployments, set the
   repository variable `ENABLE_AWS_DEPLOYMENTS` to `true`. Pushes to `main`
   then deploy staging after all required variables and CI checks are in place.
   Without that exact opt-in, deployment jobs stay skipped and checks still run.
7. Verify the staging URL, login, API health (`/health`), database persistence,
   and relevant application flows. Only then create and push a version tag:

   ```bash
   git tag v1.2.3
   git push origin v1.2.3
   ```

   The production job rejects tags whose commit is not on `main` and waits on
   the configured production environment approval.

## Backend configuration and data

Local development can use `backend/.env.example` and SQLite. ECS injects a
unique generated API signing key and PostgreSQL credentials from Secrets
Manager, sets `COOKIE_SECURE=true`, and requires TLS for database connections.
Never commit `.env` files, signing keys, database passwords, AWS access keys,
or token files.

Alembic migrations run automatically before the API starts. PostgreSQL startup
uses an advisory lock so simultaneous ECS tasks cannot run migrations at the
same time. Fresh databases receive the frozen initial schema and later
migrations. An existing pre-Alembic database is stamped at the initial revision
only if all legacy tables are present, then upgraded. Add and review a
backward-compatible migration for every schema change; do not use `create_all`
as a substitute for schema migrations.
RDS deletion protection and retained snapshots are not a substitute for
testing restore procedures.

Operational feed events are persisted in PostgreSQL in the same transaction
as their source changes. The feed shows events from the last seven days; older
rows are pruned on the next operational write. The authenticated WebSocket and
SSE endpoints are `/api/v1/ws` and
`/api/v1/admin/events/stream`; the browser defaults to same-origin WebSocket
so no extra public URL setting is required.

For API failures, the frontend's `ApiError.requestId` matches the response
`X-Request-ID` header and the backend log entry. Use that ID to correlate a
generic `INTERNAL_ERROR` shown to an operator with the server traceback; the
traceback is logged server-side and never returned in the API response.

## Daily checks and release commands

```bash
npm ci
npm run typecheck
npm run lint
npm test
npm run build

cd backend
python -m pip install -r requirements-dev.txt
python -m pytest tests
cd ..

cd infrastructure
npm ci
npm run typecheck
```

Use Conventional Commit messages (`fix(api): ...`, `feat(catalog): ...`,
`ci: ...`). Commit-message lint remains advisory because historical commits
pre-date the convention. Keep third-party GitHub Actions pinned to immutable
commit SHAs.

## Operations and rollback

- Check ECS service events, target-group health, and CloudWatch logs before
  changing task counts or restarting a service.
- The ECS deployment circuit breaker rolls back a deployment that cannot
  become healthy. Redeploy the last known-good commit/tag to roll back
  application code.
- Database changes are not automatically rolled back with application code.
  Use a tested RDS snapshot/point-in-time restore procedure for data incidents.
- Configure alarms for ALB 5xx/target health, ECS task failures, RDS storage,
  CPU/connections, and AWS budget thresholds before production use.
- A successful CI run is evidence for the tested checks only; it cannot
  guarantee that a deployment is error-free or that AWS is configured
  correctly. Confirm health and critical user journeys after every release.
