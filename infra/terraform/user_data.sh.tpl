#!/usr/bin/env bash
# ── Free-tier app boot script (idempotent — safe across reboots) ─────────────
# Installs Docker + Caddy, clones the backend, fetches DATABASE_URL from SSM,
# writes Backend/.env, starts api + worker + beat + LOCAL Redis container,
# runs migrations. Caddy reverse-proxies :80 (and :443 when a domain is set).
set -euo pipefail
exec > >(logger -t hyperlocal-boot) 2>&1
logger -t hyperlocal-boot "boot script starting"

REGION="${region}"
PROJECT="${project}"
ENVIRONMENT="${environment}"
APP_DIR="${app_dir}"
REPO="${repo_url}"
BRANCH="${branch}"
DB_URL_PARAM="${db_url_param}"
S3_BUCKET="${s3_bucket}"
CADDY_CFG="${caddy_config}"

# 0) Base tooling — git (repo clone) + AWS CLI (SSM parameter fetch, steps 3-4).
#    Ubuntu 24.04 ships NEITHER preinstalled; noble dropped the 'awscli' apt
#    package entirely → snap (v2) primary, pip fallback. The earlier boot
#    failed here ("aws: command not found" then "no installation candidate").
if ! command -v git >/dev/null; then
  apt-get update -y
  apt-get install -y git snapd
fi
if ! command -v aws >/dev/null; then
  snap install aws-cli --classic || {
    apt-get install -y python3-pip
    pip3 install --break-system-packages awscli
  }
fi

# 1) Docker + compose plugin
if ! command -v docker >/dev/null; then
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg openssl
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable" > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
fi

# 2) Caddy (reverse proxy; auto-TLS once the domain variable is configured)
if ! command -v caddy >/dev/null; then
  apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -y
  apt-get install -y caddy
fi
mkdir -p /etc/caddy
echo "$CADDY_CFG" > /etc/caddy/Caddyfile
systemctl enable caddy
systemctl restart caddy

# 3) Clone / update the backend (PAT from SSM only when the repo is private)
mkdir -p "$APP_DIR"
if [ ! -d "$APP_DIR/Backend" ]; then
  TOKEN="$(aws ssm get-parameter --name /$PROJECT/$ENVIRONMENT/github_token --with-decryption --region "$REGION" --query Parameter.Value --output text)"
  if [ -n "$TOKEN" ] && [ "$TOKEN" != "PLACEHOLDER_REPLACE_WITH_GITHUB_PAT" ]; then
    git clone --branch "$BRANCH" "https://x-access-token:$TOKEN@github.com/Akasharyan47/hyperlocal_customer_app.git" "$APP_DIR"
  else
    git clone --branch "$BRANCH" "$REPO" "$APP_DIR" # public repo: no PAT needed
  fi
fi

# 4) Fetch the private RDS connection string from SSM and write Backend/.env
DB_URL="$(aws ssm get-parameter --name "$DB_URL_PARAM" --with-decryption --region "$REGION" --query Parameter.Value --output text)"
DB_URL_SYNC="$(echo "$DB_URL" | sed 's/postgresql+asyncpg:/postgresql:/')"
umask 077
cat > "$APP_DIR/Backend/.env" <<EOF
ENVIRONMENT=$ENVIRONMENT
DATABASE_URL=$DB_URL
DATABASE_URL_SYNC=$DB_URL_SYNC
REDIS_URL=redis://redis:6379/0
CELERY_BROKER_URL=redis://redis:6379/1
CELERY_RESULT_BACKEND=redis://redis:6379/2
RATE_LIMIT_STORAGE_URI=redis://redis:6379/3
OTP_STORAGE_URI=redis://redis:6379/4
TRUST_X_FORWARDED_FOR=true
JWT_SECRET_KEY=$(openssl rand -hex 32)
STORAGE_PROVIDER=s3
S3_BUCKET_NAME=$S3_BUCKET
S3_REGION=$REGION
# Production posture: real OTP flow (no universal '123456'). Email/SMS delivery
# providers are stubs today; wire SendGrid/Twilio before expecting OTP delivery.
OTP_DEV_MODE=false
EOF

# 5) Run the app stack (api + worker + beat + LOCAL Redis; RDS is managed)
cd "$APP_DIR/Backend"
docker compose -f docker-compose.cloud.yml up -d --build

# 6) Migrations run inside the one-shot "migrate" service of the same stack.
logger -t hyperlocal-boot "boot complete"
