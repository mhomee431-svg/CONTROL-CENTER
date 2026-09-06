# Hyperlocal Product Discovery Platform — Production Release

## Release Process Overview

Every production release follows a **15-step verified pipeline**. Steps 1–8 run
automatically in CI (`reusable-backend-checks.yml`); steps 9–14 use the CD
workflow (`backend-cd.yml`) with a **protected environment approval gate**;
step 15 is the post-deploy verification + rollback readiness check.

```
 1. Run tests (unit + integration + E2E)
 2. Run database migrations (rehearsal on clean DB)
 3. Verify backups exist (RDS + S3)
 4. Verify health checks (/health, /ready)
 5. Verify HTTPS (Caddy auto-TLS, HSTS)
 6. Verify DNS (Route53 A record)
 7. Verify secrets (SSM, no secrets in git)
 8. Verify CORS (production origins only)
 9. Verify authentication (JWT + OTP)
10. Verify authorization (RBAC + IDOR guards)
11. Verify S3 (private bucket, signed URLs)
12. Verify PostGIS (geometry queries + GiST index)
13. Verify Redis (cache + rate limit + OTP stores)
14. Verify monitoring (CloudWatch logs + metrics + alarms)
15. Verify rollback (previous image + restore drill)
```

---

## Pre-Release Gate

### Test Suite
```bash
cd Backend
ENVIRONMENT=test HYPERLOCAL_ENV=test python -m pytest -v
```
All 45+ test files must pass.

### Security Audit
```python
from app.core.security_audit import run_security_audit
report = run_security_audit()
assert report.is_pass, report.to_dict()
```

### Migration Rehearsal
```bash
python scripts/recovery_test.py --report-file recovery_report.json
python scripts/migration_rehearsal.py --full-chain-rollback
```

### Migration Safety Scan
```bash
python scripts/migration_safety_check.py
```
Any `DANGEROUS` migration blocks auto-deploy until manually approved.

### Secret Scan
Gitleaks + `scripts/security/scan_secrets.py --history` must report zero findings.
---

## Release Checklist (pre-deploy acceptance)

| # | Check | How to verify | Pass criteria |
|---|-------|---------------|---------------|
| 1 | Backend builds | `docker build -t hyperlocal-backend:latest Backend` | Image builds, non-root |
| 2 | Flutter builds | `scripts/build_customer_app.bat production` | APK produced, prod URL injected |
| 3 | Migrations pass | `alembic upgrade head` on scratch DB | Revision == head |
| 4 | PostGIS works | `SELECT postgis_version();` on RDS | 3.4 USE_GEOS |
| 5 | Redis works | `redis-cli ping` on EC2 | PONG |
| 6 | S3 works | presigned POST roundtrip via /media/upload-url | Upload + confirm + GET |
| 7 | HTTPS works | `curl -sI https://api.hyperlocal.in/health` | HTTP 200 + TLS 1.3 |
| 8 | Domain works | `nslookup api.hyperlocal.in` | Resolves to EIP |
| 9 | Authentication works | OTP send/verify for test phone | Tokens issued |
| 10 | Shopkeeper works | Register to shop to product | 201 across flows |
| 11 | Customer search works | /search/v2/products q=paracetamol | Results with distance |
| 12 | Location works | POST /shops/{id}/location with GPS accuracy | PostGIS updated |
| 13 | Nearby search works | /shops/nearby radius 5 km | Sorted by distance |
| 14 | Inventory works | Update inventory to refresh index | Availability reflects |
| 15 | Price works | PUT price to price_history row | History preserved |
| 16 | Barcode works | /search/v2/barcode/{barcode} | Product + shops |
| 17 | Admin works | Admin login to /admin/dashboard/metrics | 200 with metrics |
| 18 | Logs work | CloudWatch group /hyperlocal/production/api | Receiving JSON |
| 19 | Monitoring works | /metrics + /health + /ready | Exposed |
| 20 | Backups work | rds describe-db-snapshots + S3 daily/ | Snapshot <= 25h |
| 21 | Restore tested | Monthly drill executed | recovery_report.json PASS |
| 22 | Security audit passed | run_security_audit() | errors == [] |
| 23 | No prod secrets in git | Gitleaks scan | Clean |
| 24 | Rollback tested | CD rollback job exercised | Previous image restored |

---

## Release Runbook (CD pipeline)

### 1. Quality gates (steps 1-8)
`backend-ci.yml` runs on push. DANGEROUS migrations never auto-apply.

### 2. Build & push immutable image
Image tag = git SHA (immutable, auditable, rollback-friendly).
```bash
docker build -t hyperlocal-backend:${GITHUB_SHA}
docker tag  hyperlocal-backend:${GITHUB_SHA} ${ECR_REGISTRY}/hyperlocal-backend:${GITHUB_SHA}
docker push ${ECR_REGISTRY}/hyperlocal-backend:${GITHUB_SHA}
```

### 3. Deploy staging to 4. Smoke-test staging to 5. Production approval
`environment: production` requires GitHub reviewers.

### 6. Deploy production to 7. Verify production
```bash
./infra/scripts/cicd_smoke_test.sh \
  --url https://api.hyperlocal.in \
  --expect-env production --sha ${GITHUB_SHA}
```

### 8. Rollback if any failure (automatic)
`rollback-production` job to `cicd_rollback.sh` with `LAST_GOOD_IMAGE`.

---

## Post-Deploy Verification

```bash
curl -s https://api.hyperlocal.in/health
curl -s https://api.hyperlocal.in/ready
curl -s "https://api.hyperlocal.in/api/v1/search/v2/products?q=shampoo&latitude=12.97&longitude=77.59&radius_km=10"
aws cloudwatch describe-alarms --alarm-name-prefix production-
```

---

## Rollback Decision Matrix

| Symptom | Action | Response |
|---------|--------|----------|
| 5xx > 1% for 5 min | Rollback last_good_image | Immediate |
| Search p95 > 1s | Inspect query plan + cache | 1 hour |
| DB connections > 80% | Scale RDS / inspect slow queries | 1 hour |
| Failed migrations | Never roll-forward; restore snapshot | 4 hours |
| Redis outage | Cache degrades safely (miss to DB) | Automatic |
| S3 outage | Uploads fail-fast; reads fall back | Automatic |

---

## Definition of Done

- [ ] All 24 checklist items verified (evidence attached)
- [ ] /ready returns status: "ready" + correct commit SHA
- [ ] Rollback drill executed for previous release
- [ ] CloudWatch shows no new error-level spikes
- [ ] Backup snapshot age < 25h
- [ ] Gitleaks clean on release commit
- [ ] SELECT postgis_version() shows 3.4
- [ ] /metrics exposes all hl_* families (incl. DB/cache/search)

---

## First-ever Production Launch (manual bootstrap)

```powershell
terraform -chdir=infra/terraform init
terraform -chdir=infra/terraform plan -out=tfplan
terraform -chdir=infra/terraform apply tfplan

aws ssm put-parameter --name /hyperlocal/production/database_url \
  --type SecureString --value "postgresql+asyncpg://..." --overwrite

powershell -ExecutionPolicy Bypass -File infra/scripts/network_verify.ps1 \
  -Region ap-south-1 -Env production
```
Migrations run via entrypoint; confirm with `docker compose exec api alembic current`.
Seed domains (staging/dev only): `python -m db_seed/seed_data.py --url "<same DB>"`.