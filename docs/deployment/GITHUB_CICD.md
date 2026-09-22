# GitHub CI/CD workflow

The repository uses a protected-branch flow:

```text
feature/customer   feature/shopkeeper   feature/backend
        \                 |                 /
                    Pull request
                         |
                      develop
                         |
                 integration validation
                         |
                      Pull request
                         |
                       main
                         |
                    AWS production
```

## Automated checks

- `platform-ci.yml` runs backend quality gates and analyze/test checks for the
  customer app, shopkeeper app, admin panel, and shared Dart models on pull
  requests targeting `develop` or `main`, and on pushes to `develop`.
- `backend-ci.yml` remains the backend-specific `main` gate.
- `flutter-customer.yml` and `flutter-shopkeeper.yml` build production APK
  artifacts after changes land on `main`.
- `flutter-admin.yml` builds and uploads the production Flutter web artifact
   after admin panel changes land on `main`.
- `backend-cd.yml` deploys the backend from `main` through staging, protected
  production approval, smoke verification, and rollback.
- `backend-deploy.yml` is the ECS driver and must be enabled only when the
  repository variable `DEPLOY_TARGET` is `ecs`.

## Required repository settings

Configure these in GitHub before enabling production deployment:

1. Protect `develop` and `main`. Require pull requests, require the
   `Platform CI / Backend quality gates`, `Platform CI / Customer app checks`,
   `Platform CI / Shopkeeper app checks`, `Platform CI / Admin panel checks`,
   and `Platform CI / Shared Dart package checks` checks, and disable direct
   pushes.
2. Protect the `production` environment with required reviewers. Protect the
   `staging` environment if staging has customer data.
3. Add an AWS OIDC trust policy that limits the deploy role to this repository
   and the intended branch/environment. Store the role ARN as
   `AWS_DEPLOY_ROLE_ARN`; do not store long-lived AWS keys.
4. Set `AWS_REGION`, deployment target variables, service or instance names,
   API URLs, and the ECR repository variables described in
   `docs/deployment/DEPLOYMENT.md`.
5. Add `CUSTOMER_API_BASE_URL`, `SHOPKEEPER_API_BASE_URL`, and
   `GOOGLE_MAPS_API_KEY` only when the production APK workflows are enabled.

Production deployment is intentionally not triggered by feature branches or
`develop`; only a reviewed change merged to `main` can reach AWS.