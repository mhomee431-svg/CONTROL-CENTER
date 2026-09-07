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
| backend-ci.yml | PR to main | Quality gates |
| backend-cd.yml | Push to main | Deploy to AWS |
| secret-scan.yml | Push/PR | Secret detection |
| flutter-customer.yml | PR to main | Customer app CI |
| flutter-shopkeeper.yml | PR to main | Shopkeeper app CI |

### Deployment Flow

1. Developer pushes to main
2. CI runs quality gates (lint, test, security)
3. Migration safety check
4. Build & push Docker image to ECR
5. Deploy to staging
6. Smoke test staging
7. Manual approval for production
8. Deploy to production
9. Verify production health
10. Automatic rollback on failure

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
