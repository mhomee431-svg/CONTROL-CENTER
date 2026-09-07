# FREE-TIER Cloud Deployment ($0 during the 6-month window)

> **Goal:** app ko AWS par **live** karna WITHOUT paid services. Jab users badhenge,
> tab production module (`infrastructure/terraform`) apply hoga — ye setup uska stepping stone hai.

## Architecture

```
Internet ──► :80 ▼ SG "hyperlocal-free-app-sg" (ONLY port 80 open)
                     │
              EC2 t3.micro (Ubuntu 24.04)          ◄── Session Manager (SSH-free console)
              ├─ docker compose:                   ◄── boot script auto-runs at start & reboot
              │    postgis/postgis:16-3.4   (db_data volume)
              │    redis:7-alpine           (redis_data volume)
              │    api  ── host :80        (uploads volume)
              │    worker + beat + one-shot migrate
              └─ backend/.env auto-generated (random JWT secret)
```

**Kya JAAN BOOCH ke nahi banaya** (har ek paisa khata hai): NAT Gateway, ALB,
RDS, ElastiCache, ECS/Fargate, Secrets Manager, interface endpoints, SSH port 22.

## 💰 Cost math (ap-south-1)

| Item | $/month |
|---|---|
| EC2 t3.micro (~$0.0104/h) | ~7.6 |
| EBS gp3 20GB | ~1.6 |
| Public IPv4 ($0.005/h) | ~3.65 |
| VPC / subnet / IGW / SG / SSM params | **0** |
| **Total** | **~$12.8** |

$100 signup credit ⇒ **~7.8 months** coverage ⇒ your whole 6-month tier is effectively FREE.
(Elastic IP attach mat karo — unattached EIP + unused IPv4 dono charge karte hain.)

## Deploy — sirf 4 steps

```powershell
# 0) identity confirm (default profile se)
aws sts get-caller-identity

# 1) plan + apply (repo root se)
terraform -chdir=infrastructure/free init
terraform -chdir=infrastructure/free plan -out=tfplan      # '~8 to add'
terraform -chdir=infrastructure/free apply tfplan          # outputs me public_ip milega

# 2) (SIRF private repo hai to) GitHub PAT daal do — Standard SecureString = free
aws ssm put-parameter --name /hyperlocal/free/github_token --type SecureString --overwrite `
  --value "<your-GitHub-PAT-with-repo-read>"

# 3) 5-8 min baad verify (build pehli baar lambi hoti hai)
powershell -ExecutionPolicy Bypass -File scripts/dev/free_verify.ps1
```

Agar step-2 PAT baad me diya aur clone fail ho chuka tha → EC2 Console me instance
**Reboot** karo; boot-script wapas chalega aur clone kar lega.

### Agar sab kuch fail ho

```
EC2 Console → hyperlocal-free-app → Connect → Session Manager
journalctl -t hyperlocal-boot -f          # boot log live
docker ps && docker logs -f $(docker ps -qf name=api)
```

## Security posture

* Sirf **port 80** public. DB/Redis ke andar hi internal, no host ports.
* **No key pair, no port 22** — shell Session Manager se (IAM role based).
* IMDSv2-only, encrypted root volume, detailed metrics OFF (credit-safe).
* JWT secret server-par random generate hota hai (`/opt/hyperlocal/secrets/.env`),
  git me kabhi nahi jaata. PAT SecureString me, rotated manually.
* OTP abhi `OTP_DEV_MODE=true` hai (test OTP **123456**) — real SMS lagane se
  PEHLE `.env` me false + provider keys set karna **zaroori** hai.

## Load aane par upgrade path (paid conversion)

1. Postgres/Redis compose se nikaalo → Phase-4 RDS + ElastiCache (`infrastructure/terraform`)
2. EC2 → ECS Fargate + ALB + NAT (existing Phase-3 code ready hai)
3. Domain lagao → Route53 + ACM HTTPS (Caddy/LE bhi ek option hai before that)

## Teardown (charges band karne ka pakka tareeka)

```powershell
terraform -chdir=infrastructure/free destroy     # instance+volumes+param delete -> billing stops
```

Sirf STOP karna *bill bachata nahi* (EC2 stopped state me bhi EBS IPv4 charge hota hai bina attach ke).
