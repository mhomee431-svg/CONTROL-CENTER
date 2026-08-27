# Hyperlocal Production Infrastructure (AWS)

Terraform-managed, private-by-default AWS topology for the **Hyperlocal Customer
API**. Nothing here hardcodes secrets, and no infrastructure is exposed publicly
except the ALB (HTTPS only).

```
                        ┌─────────── HTTPS 443/80 ───────────┐
                        ▼                                    │
                    ALB (public subnets)          Internet gateway ─► NAT ─► private subnets
                        │ forward:443→8000
                        ▼
              ECS Fargate "web" (private subnet)   ─┐
        +────────────────+───────────────────────+  │ only app SG
        │                │                       │  ▼
   RDS Postgres 16   ElastiCache Redis           awslogs (CloudWatch)
   (data subnet)     (data subnet)
        ▲                       ▲
        └──── app SG only ──────┘   (no 0.0.0.0/0 on DB/Redis)

   S3 "uploads" (private, SSE-KMS) ← IAM task role (no static keys)
   Secrets Manager (backend bundle + DATABASE_URL) ← ECS secrets / helper
```

## Components

| Layer | Resource | Notes |
|-------|----------|-------|
| Networking | VPC, public/private/data subnets, IGW, NAT, route tables | data subnets host RDS/Redis only |
| Compute | ECS Fargate — `web`, `worker`, `beat` | awsvpc, no public IPs |
| Data | RDS PostgreSQL 16 (+PostGIS via migration), ElastiCache Redis 7 | app SG only, SSL enforced |
| Storage | S3 private bucket, SSE-KMS | IAM role; app returns presigned URLs |
| Secrets | Secrets Manager (2 secrets) | operator-populated, ECS-injected |
| Identity | Task exec + task runtime IAM roles | least privilege, no static keys |
| Edge | ALB, ACM cert, Route53 | HTTPS with redirect from :80 |
| Scaling | App Autoscaling (CPU 70%) | 1–4 web tasks |

## 🅰 Manual inputs you must provide (before `terraform apply`)

Per the project rules I will not invent or paste secrets. Prepare these **in the
AWS console / provider consoles**:

1. **AWS account + IAM role** for Terraform (least-privilege; not root). Set
   `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` **as environment variables** on
   the machine running Terraform — never in files.
2. **Region** (recommend `ap-south-1` for India or your local market).
3. **Domain + DNS** (root `example.com`). Either delegate to a **Route53 hosted
   zone** (give us the Zone ID) or point `api.` A-record to the ALB DNS after apply.
4. **Provider/KMS keys** — you create these and paste them into the **Secrets
   Manager bundle** (see below). We never need the raw values in chat.

## Provision order

```bash
aws s3api create-bucket --bucket hyperlocal-terraform-state --region <region>  # or any backend
# (create + dynamodb lock table if you enable the s3 backend block in providers.tf)

cd infra/terraform
cp terraform.tfvars.example terraform.tfvars   # fill region/domain/zone
terraform init
terraform plan
terraform apply
```

## After apply — populate secrets & deploy

1. **Backend runtime bundle** (`hyperlocal/<environment>` … the `app_secret_arn`
   secret). Flat JSON, keys become env vars (see `.env.example` for all names).
   Terraform created it empty — paste via console/CLI:

   ```bash
   aws secretsmanager put-secret-value \
     --secret-id <app_secret_arn> \
     --secret-string '{
       "JWT_SECRET_KEY":"<long random>",
       "SMS_PROVIDER":"twilio","TWILIO_AUTH_TOKEN":"...",
       "EMAIL_PROVIDER":"sendgrid","SENDGRID_API_KEY":"...",
       "OTP_DEV_MODE":"false",
       "STORAGE_PROVIDER":"s3"
     }'
   ```

   > `DATABASE_URL` is handled separately — Terraform wrote it into the
   > `…/database` secret and ECS injects it natively. Don't paste it here.

2. Deploy the image (CI does this; or manually):
   ```bash
   aws ecr get-login-password --region <region> | docker login --username AWS --password-stdin <ecr_registry_url>
   docker build -f Backend/Dockerfile -t <ecr_registry_url>/hyperlocal-backend:<sha> Backend
   docker push <ecr_registry_url>/hyperlocal-backend:<sha>
   # set backend_image_tag = <sha> in tfvars → apply (or use the CodeDeploy pipeline)
   ```

3. Run migrations once:
   ```bash
   aws ecs run-task --cluster <cluster> --task-definition <web_task> \
     --overrides '{ "containerOverrides": [ { "name":"api","command":["sh","-c","alembic upgrade head"] } ] }'
   ```

4. Health check: `curl https://api.example.com/health` → then `/ready`.

## Security guarantees implemented

- RDS/Redis not reachable from the internet (no public SG, private subnets).
- Static keys never needed at runtime (IAM roles; default credential chain).
- `STORAGE_PROVIDER=s3`, `S3_ACL=private`; images via **presigned GET URLs**.
- Secrets only in Secrets Manager, KMS-encrypted, ECS-injected.
- HTTPS enforced (HTTP → 301), modern TLS policy, HSTS (app config).
- Flutter apps receive **no AWS credentials** — only the public HTTPS API URL.