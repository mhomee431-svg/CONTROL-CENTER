# PHASE 3 — AWS NETWORK FOUNDATION (Free-Tier Edition)

**Status:** Authoring complete (IaC + verification runbook + docs). Live
`apply` + connectivity checks need operator AWS credentials or the CI
workflow. **Refactored to be 100% 12-month Free-Tier compliant** — the paid
design (NAT, ALB, ECS, ElastiCache) lives in git history.

## 1. Decisions (non-negotiable)

| Decision | Rationale |
|---|---|
| **$0/month** | Brand-new account; strict 12-month Free-Tier usage. |
| **No NAT Gateways** | ~$32/mo each. The single app EC2 sits in a PUBLIC subnet → IGW gives free egress. |
| **No ALB** | ~$16/mo. A stable **Elastic IP** + Caddy (reverse proxy, auto-TLS) on the instance. |
| **No ElastiCache** | No free tier. Redis runs as a **local Docker container** on the app EC2, bound to the compose network only (never host-published ⇒ never public). |
| **RDS stays managed** | db.t3.micro + 20GB gp2 = free (750h/mo), `publicly_accessible = false`, isolated data subnet (no default route), app-SG-only ingress on 5432. |
| **Private S3** | Free **S3 Gateway VPC endpoint**; bucket has all 4 public-access blocks + TLS-only policy; instance-role creds (no static keys). |
| **Only-required-traffic SGs** | app: 80/443 in from the world (Caddy). RDS: 5432 from app SG only. No SSH port — Session Manager. |
| **2 AZs** | App subnet (AZ a) + data subnet (AZ b) — satisfies the db-subnet-group multi-AZ requirement at zero cost. |
| **Flow logs retained** | VPC Flow Logs (ALL) → CloudWatch, 14-day retention (free-tier safe). |
| **Env separation** | `development` (local) · `staging` · `production` via distinct tfvars, name prefixes, SSM paths, state keys. |

## 2. Architecture

```
            Internet
               │
               ▼
   ┌────────────────────────── AWS VPC 10.0.0.0/16 ──────────────────────────┐
   │   AP-SOUTH-1A                          AP-SOUTH-1B                      │
   │  ┌────── public-app ──────────────┐   ┌────── data (ISOLATED) ───────┐  │
   │  │ 10.0.1.0/24  EC2 t3.micro      │   │ 10.0.20.0/24  RDS Postgres16 │  │
   │  │  EIP + Caddy :80/:443          │   │  db.t3.micro, app-SG only,   │  │
   │  │  + local Redis container       │   │  no public IP, no internet   │  │
   │  │  + api/worker/beat containers  │   │  route (no default route)    │  │
   │  └───────────▲ IGW route ────────┘   └──────────────────────────────┘  │
   │              │                                                        │
   │  S3 Gateway VPC endpoint → data RT (private S3 path, free)             │
   │  VPC Flow Logs (ALL) → CloudWatch, 14d retention                       │
   └─────────────────────────────────────────────────────────────────────────┘
```

## 3. Private connectivity matrix

| From → To | Path | Enforced by |
|---|---|---|
| app EC2 → RDS | VPC-local, 5432 | rds SG `security_groups=[app SG]`; data RT has no internet route; `publicly_accessible=false` |
| app EC2 → Redis | in-host Docker network | compose network only; no host port published |
| app EC2 → S3 | S3 Gateway endpoint route (in-VPC) + instance-role creds | endpoint route; bucket TLS-only policy |
| Internet → app | 80/443 only | app SG ingress (Caddy/ACME) |
| Internet → RDS/Redis | impossible | no public IP, isolated RT, SGs, local-only Redis |

## 4. Cost math (ap-south-1, 12-month free tier)

| Item | Allowance | $/mo |
|---|---|---|
| EC2 t3.micro (750h) | free tier | 0 |
| EBS gp2 20GB (≤30GB) | free tier | 0 |
| Elastic IP (attached, running) | free | 0 |
| RDS db.t3.micro 750h + 20GB gp2 | free tier | 0 |
| S3 5GB + gateway endpoint | free tier | 0 |
| SSM SecureString params | free | 0 |
| CloudWatch flow logs (14d) | free tier | 0 |
| **Total** | | **$0** |

After month 12: ≈ $13/mo (EC2 7.6 + EBS 1.6 + IPv4 3.65). RDS db.t3.micro
(~$12.5) is then the first paid line — see the upgrade path in
`infra/README.md`.

## 5. What was REMOVED vs the previous (paid) design

| Removed | Old monthly cost | Replacement |
|---|---|---|
| NAT Gateways ×2 | ~$64 | IGW + public app subnet |
| ALB | ~$16 | Elastic IP + Caddy |
| ElastiCache Redis | ~$12 | local Docker `redis:7-alpine` |
| ECS Fargate + ECR | ~$0-15 | single EC2 + `docker compose` |
| Secrets Manager ($0.40/secret) | ~$1 | SSM SecureString (free) |
| SSE-KMS on S3 (request $) | ~$0-1 | AES256 SSE (free) |

## 6. Environment separation

| Env | How | SSM path |
|---|---|---|
| development | local Docker (`Backend/docker-compose.yml`) | — |
| staging | `terraform apply -var-file=terraform.tfvars.staging` | `/hyperlocal/staging/*` |
| production | `terraform apply -var-file=terraform.tfvars.production` | `/hyperlocal/production/*` |

## 7. RDS public-exposure exception policy (unchanged)

There is **no** exception configured and none is needed. If a temporary,
documented, justified exception is ever required (e.g. one-off data import
from an office IP): set `publicly_accessible = true` + only that `/32` in the
RDS SG, record justification + expiry in this doc, and revert in the same
session. Never `0.0.0.0/0`.

## 8. Verification (runbook)

`infra/scripts/network_verify.ps1` (CI runs it on every push):

1. VPC + CIDR
2. Subnet tiering (public-app + data, >=2 AZs)
3. **IGW present AND zero NAT gateways (hard fail = cost guard)**
4. Data route table has no `0.0.0.0/0` (isolation)
5. S3 Gateway endpoint present
6. SG audit: app SG public ports ⊆ {80,443}; RDS/Redis SG has **no** `0.0.0.0/0` (hard fail)
7. Flow logs active
8. `PubliclyAccessible=false` per RDS instance; **zero ElastiCache clusters** (hard fail)
9. Live `/ready` via `-ApiUrl http://<EIP>` (proves app→RDS→Redis) + uploads-bucket PAB/TLS policy

## 9. Run it

```powershell
aws sts get-caller-identity                      # credentials via profile/env
terraform -chdir=infra/terraform init
terraform -chdir=infra/terraform plan -out=tfplan
terraform -chdir=infra/terraform apply tfplan
powershell -ExecutionPolicy Bypass -File infra/scripts/network_verify.ps1 `
  -Region ap-south-1 -Env production -ApiUrl http://<app_public_ip>
```

**Reminder:** no plaintext AWS credentials belong in any script. Use
`~/.aws/credentials` profiles or short-lived env vars, and rotate any key that
has ever touched a file.

## 10. Verification record

- [x] Static: `terraform fmt -check` exit 0, `terraform validate` Success
- [x] Runbook parses (`Parser::ParseFile` 0 errors)
- [ ] Live checks — pending operator AWS credentials (§9)

