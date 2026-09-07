# Hyperlocal Infrastructure — FREE-TIER (AWS 12-month, $0/month)

Terraform-managed AWS topology for the **Hyperlocal Customer API**, engineered to
stay inside the **AWS 12-month Free Tier**. Nothing is publicly exposed except
the app instance's Caddy reverse proxy (80/443). No NAT gateways, no ALB, no
ElastiCache, no Secrets Manager, no paid extras.

> Paid-tier design (ECS Fargate + ALB + NAT + ElastiCache) is preserved in git
> history — `git log -- infrastructure/terraform` — and is the documented upgrade path.

```
Internet ──► 80/443  ▼ SG "…-app-sg" (ONLY 80/443 open; no SSH port)
                     │
             Elastic IP ◄── free while attached (stop/start-safe address)
                     │
        EC2 t3.micro (public subnet, Ubuntu 24.04)  ◄── shell = Session Manager
        ├─ Caddy (systemd)  :80/:443 ──► 127.0.0.1:8000   (auto-TLS with a domain)
        ├─ docker compose (docker-compose.cloud.yml):
        │    redis:7-alpine         ◄── LOCAL container (never host-published)
        │    api  → 127.0.0.1:8000  (uploads volume)
        │    worker + beat + one-shot migrate
        │
        ├─► RDS PostgreSQL 16 (db.t3.micro, PRIVATE data subnet, app-SG only)
        │    DATABASE_URL fetched from SSM SecureString at boot
        └─► S3 uploads bucket ◄── free S3 Gateway VPC endpoint (in-VPC path)
                                   creds via the instance role (no static keys)
```

## Free-tier budget (ap-south-1)

| Item | Allowance used | $/month |
|---|---|---|
| EC2 t3.micro | 750 h/mo | 0 |
| EBS gp2 root 20GB | 30 GB/mo | 0 |
| Elastic IP | attached to running instance | 0 |
| RDS db.t3.micro + 20GB gp2 | 750 h + 20 GB | 0 |
| S3 uploads (AES256, no versioning) | 5 GB + 20k GET | 0 |
| SSM parameters (SecureString, standard) | free | 0 |
| VPC Flow Logs (14-day retention) | free tier | 0 |
| S3 Gateway endpoint / IGW / SGs | always free | 0 |
| **Total** | | **$0** |

Post-12-months steady state ≈ **$13/mo** (EC2 ~7.6 + EBS ~1.6 + IPv4 ~3.65 +
RDS ~12.5 → RDS becomes the biggest line; see "Upgrade path").

## Files

| File | Purpose |
|---|---|
| `terraform/main.tf` | VPC, public app subnet, isolated data subnet, IGW, route tables |
| `terraform/security_groups.tf` | app (80/443 in) + rds (5432 from app SG only) |
| `terraform/ec2.tf` | t3.micro + Caddy boot script + EIP + instance role (SSM/S3 least-privilege) |
| `terraform/rds.tf` | RDS Postgres 16 db.t3.micro, private, SSM SecureString for DATABASE_URL |
| `terraform/s3.tf` | private uploads bucket (all 4 public-access blocks + TLS-only policy) |
| `terraform/vpc_endpoints.tf` | S3 Gateway endpoint (private S3, free) |
| `terraform/flow_logs.tf` | VPC flow logs → CloudWatch (14-day retention) |
| `terraform/redis.tf` | note: Redis = local Docker container (ElastiCache has no free tier) |
| `terraform/user_data.sh.tpl` | idempotent boot: Docker, Caddy, clone, .env from SSM, compose up |
| `backend/docker-compose.cloud.yml` | api + worker + beat + migrate + **local redis** |
| `scripts/network_verify.ps1` | Phase-3 verification runbook (see below) |

## Deploy

```powershell
# 0) identity (use a profile, NOT plaintext keys in scripts)
aws sts get-caller-identity

# 1) plan + apply
terraform -chdir=infrastructure/terraform init
terraform -chdir=infrastructure/terraform plan -out=tfplan
terraform -chdir=infrastructure/terraform apply tfplan
# outputs: app_public_ip (EIP), database_endpoint, s3_bucket_name, ...

# 2) (only if the repo is private) store the GitHub PAT
aws ssm put-parameter --name /hyperlocal/production/github_token --type SecureString `
  --value "<PAT-with-repo-read>" --overwrite

# 3) ~5-8 min after first boot, verify everything
powershell -ExecutionPolicy Bypass -File infrastructure/scripts/network_verify.ps1 `
  -Region ap-south-1 -Env production -ApiUrl http://<app_public_ip>
```

Environment separation: run IaC per environment with distinct tfvars —
`terraform apply -var-file=terraform.tfvars.staging` — name prefixes, SSM
paths (`/hyperlocal/<env>/*`) and state keys differ automatically.

### If boot fails

```
EC2 Console → hyperlocal-production-app → Connect → Session Manager
journalctl -t hyperlocal-boot -f
docker ps && docker logs -f hyperlocal-cloud-api-1
```

## Security posture

* Only **80/443** are public (Caddy). No SSH port — shell via Session Manager
  (IAM role based, free). Optional `admin_cidr` variable exists for port 22.
* RDS is `publicly_accessible = false`, in a data subnet whose route table has
  **no default route**, reachable only from the app SG on 5432.
* Redis is a local container — never published to a host port.
* S3 bucket: all four public-access blocks + `aws:SecureTransport=false` deny.
* `JWT_SECRET_KEY` is generated at boot on the server; `DATABASE_URL` travels
  only via SSM SecureString; no secrets in git.
* IMDSv2 required; root volume encrypted; detailed monitoring off.

## Upgrade path (when traffic/paid tier arrives)

1. Recreate NAT + ALB + ECS + ElastiCache from git history (`infrastructure/terraform`
   before the free-tier refactor) or the Phase-3 paid design.
2. Move Redis from compose → ElastiCache (`REDIS_URL` swap only).
3. Point a domain via Route53/ACM — or keep Caddy, which issues HTTPS for free.
4. RDS: raise class (`db.t3.small`+), enable backups + Multi-AZ.

## Teardown

```powershell
terraform -chdir=infrastructure/terraform destroy   # releases EIP, deletes RDS/EBS → billing stops
```

A stopped EC2 still bills its EBS volume; **destroy** is the only full stop.
