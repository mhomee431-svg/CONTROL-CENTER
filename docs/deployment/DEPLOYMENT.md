# Hyperlocal Product Discovery Platform — Deployment

## Deployment Overview

The platform is deployed on AWS using Terraform for infrastructure as code and GitHub Actions for CI/CD.

## Architecture (Stage A — Cost-Conscious)

```
Internet
    │
    ▼
Route53 (api.hyperlocal.in)
    │
    ▼
EC2 t3.micro (Ubuntu 24.04)
├── Caddy (reverse proxy + auto-TLS)
├── Docker Compose
│   ├── API (FastAPI + Uvicorn, port 8000)
│   ├── Worker (Celery)
│   ├── Beat (Celery scheduler)
│   └── Redis (local container, port 6379)
├── RDS PostgreSQL 16 + PostGIS (private)
└── S3 (object storage)
```

## Prerequisites

- AWS Account with Free Tier
- Terraform >= 1.6
- Docker & Docker Compose
- GitHub account
- Domain (optional, for HTTPS)

## Infrastructure Deployment

### 1. Configure AWS Credentials

```powershell
aws configure --profile hyperlocal
# OR use environment variables
$env:AWS_ACCESS_KEY_ID = "..."
$env:AWS_SECRET_ACCESS_KEY = "..."
$env:AWS_REGION = "ap-south-1"
```

### 2. Initialize Terraform

```powershell
cd infrastructure/terraform
terraform init
```

### 3. Plan and Apply

```powershell
terraform plan -out=tfplan
terraform apply tfplan
```

### 4. Store Secrets in SSM

```powershell
# Database URL (auto-generated)
aws ssm put-parameter --name "/hyperlocal/production/database_url" `
  --type SecureString --value "postgresql+asyncpg://..." --overwrite

# GitHub PAT (if repo is private)
aws ssm put-parameter --name "/hyperlocal/production/github_token" `
  --type SecureString --value "<PAT>" --overwrite
```

### 5. Verify Deployment

```powershell
powershell -ExecutionPolicy Bypass -File infrastructure/scripts/network_verify.ps1 `
  -Region ap-south-1 -Env production -ApiUrl http://<app_public_ip>
```

## CI/CD Pipeline

### GitHub Actions Workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| backend-ci.yml | PR or push to `develop` / `main` | Quality gates (analyze, tests, security, migration rehearsal) |
| backend-cd.yml | Push to `develop` / `main` | Staged deploy: staging → smoke → E2E → approval → production |
| backend-deploy.yml | Push to `develop` / `main` when `DEPLOY_TARGET=ecs` | Same staged deploy on ECS/Fargate |
| secret-scan.yml | Push/PR | Secret detection |
| flutter-customer.yml | PR to `develop`/`main`; push builds the branch's APK | Customer app CI + staging (`develop`) / production (`main`) APK |
| flutter-shopkeeper.yml | PR to `develop`/`main`; push builds the branch's APK | Shopkeeper app CI + staging (`develop`) / production (`main`) APK |

See [`BRANCHING.md`](BRANCHING.md) for the branch rules, required checks and
release runbooks.

### Deployment Flow

1. Developer opens a PR from `feature/*` into `develop` (or `main`)
2. CI runs the quality gates (lint, tests, security, migration rehearsal)
3. Merge to `develop` → the CD pipeline starts
4. Migration safety check (dangerous migrations need `migrate_approved=true`)
5. Build & push the Docker image to ECR (`:<sha>` + `:develop`)
6. Deploy to staging (SSM Run Command on `hyperlocal-staging-app`)
7. Smoke test staging (health, readiness, deployment SHA)
8. **E2E contract battery** — the deployed API must match
   `packages/api_contracts/openapi.json` (the staging release gate)
9. PR `develop` → `main` for final review, then merge (CI runs again)
10. CD re-validates on staging, then **manual approval** on the protected
    `production` environment
11. Deploy to production (`hyperlocal-production-app`), image tagged `:latest`
12. Verify production health + E2E, then automatic rollback on any failure

## Environment Variables

### Production (.env.production)

```env
ENVIRONMENT=production
DEBUG=false
API_PREFIX=/api/v1

# Database (from SSM)
DATABASE_URL=postgresql+asyncpg://...@rds-endpoint:5432/hyperlocal

# Redis (local container)
REDIS_URL=redis://127.0.0.1:6379/0
CELERY_BROKER_URL=redis://127.0.0.1:6379/1
CELERY_RESULT_BACKEND=redis://127.0.0.1:6379/2

# Security
JWT_SECRET_KEY=<from SSM>
OTP_MODE=live

# Storage
STORAGE_PROVIDER=s3
S3_BUCKET_NAME=<uploads-bucket>
S3_REGION=ap-south-1

# CORS
CORS_ORIGINS=https://app.hyperlocal.in,https://shopkeeper.hyperlocal.in
```

## Monitoring

### Health Endpoints
- `/health` — Liveness probe
- `/ready` — Readiness probe (checks DB, Redis, PostGIS)
- `/metrics` — Prometheus metrics (protected)

### CloudWatch
- VPC Flow Logs (14-day retention)
- Application logs (via Docker)

### Alarms
- API 5xx error rate > 1%
- Database connections > 80%
- CPU utilization > 80%

## Backup & Recovery

### RDS
- Automated backups: 7-day retention
- Point-in-time recovery enabled
- Final snapshot on destroy

### S3
- Lifecycle policies for incomplete uploads
- No versioning (cost optimization)

### Recovery Procedures
1. Database: Use `infrastructure/scripts/rds_restore.sh`
2. Application: Redeploy from ECR
3. Infrastructure: `terraform apply`

## Rollback

### Application Rollback
```powershell
./infrastructure/scripts/cicd_rollback.sh --target compose `
  --region ap-south-1 `
  --instance-tag hyperlocal-production-app `
  --image <previous-image-uri>
```

### Database Rollback
- Use point-in-time recovery
- Or restore from snapshot

## Teardown

```powershell
terraform destroy
```

**Warning**: This deletes all resources including RDS data. Ensure backups exist.
