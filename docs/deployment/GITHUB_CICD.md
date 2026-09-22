# GitHub CI/CD workflow

The repository uses a protected-branch flow (details, gates and runbooks:
[`BRANCHING.md`](BRANCHING.md)):

```text
feature/customer   feature/shopkeeper   feature/backend
        \                 |                 /
                    Pull request
                         |
                platform-ci.yml gates
                         |
                      develop
                         |
             auto deploy -> staging
                         |
          smoke + E2E contract battery   <- the release gate
                         |
                    Pull request
                         |
                        main
                         |
        approval -> deploy -> verify -> production (AWS)
```

## Automated checks

- `platform-ci.yml` runs backend quality gates and analyze/test checks for the
  customer app, shopkeeper app, admin panel, and shared Dart models on pull
  requests targeting `develop` or `main`, and on pushes to `develop`.
- `backend-ci.yml` remains the backend-specific gate (PR + push on `develop` and
  `main`).
- `flutter-customer.yml` and `flutter-shopkeeper.yml` build the **staging** APK
  (`APP_ENV=staging` → `https://staging-api.hyperlocal.in`) on `develop` and the
  **production** APK on `main`.
- `flutter-admin.yml` builds the Flutter web artifact: `admin-panel-web-staging`
  on `develop`, `admin-panel-web-release` on `main`.
- `backend-cd.yml` runs on `develop` and `main`: quality battery → staging →
  smoke → **E2E contract battery** → (on `main`, after approval) production →
  verify → automatic rollback. A failed staging gate blocks production even if
  it is approved.
- `backend-deploy.yml` is the ECS driver and must be enabled only when the
  repository variable `DEPLOY_TARGET` is `ecs`.

## Required repository settings

Configure these in GitHub before enabling production deployment:

1. Protect `develop` and `main`. Require pull requests, require the
   `Platform CI / Backend quality gates`, `Platform CI / Customer app checks`,
   `Platform CI / Shopkeeper app checks`, `Platform CI / Admin panel checks`,
   and `Platform CI / Shared Dart package checks` checks, and disable direct
   pushes. `scripts/setup_branch_protection.ps1` applies this (use `-Discover`
   to take the exact names GitHub reports).
2. Protect the `production` environment with required reviewers (the release
   gate). Protect the `staging` environment if staging has customer data.
3. Add an AWS OIDC trust policy that limits the deploy role to this repository
   and the intended branch/environment. Store the role ARN as
   `AWS_DEPLOY_ROLE_ARN`; do not store long-lived AWS keys.
4. Set `AWS_REGION`, deployment target variables, service or instance names,
   API URLs, and the ECR repository variables described in
   `docs/deployment/DEPLOYMENT.md`.
5. Add `CUSTOMER_API_BASE_URL`, `SHOPKEEPER_API_BASE_URL`, and
   `GOOGLE_MAPS_API_KEY` only when the production APK workflows are enabled.

Production deployment is intentionally not triggered by feature branches or
`develop`; only a reviewed change merged to `main` can reach AWS. Pushes to
`develop` *do* deploy to **staging** (the pre-production gate) and publish the
staging app artifacts — that is how a change earns its way to `main`.