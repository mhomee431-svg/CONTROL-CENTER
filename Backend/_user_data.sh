#!/bin/bash
# Fixed boot script v2 - production-ready
set -x
exec > /var/log/boot-v2.log 2>&1

echo "=== BOOT V2 START $(date) ==="

# 0) Update SSM agent FIRST (critical for remote debugging)
systemctl stop snap.amazon-ssm-agent.amazon-ssm-agent.service 2>/dev/null || true
snap remove amazon-ssm-agent 2>/dev/null || true
apt-get update -y
apt-get install -y snapd
snap install amazon-ssm-agent --classic
systemctl enable --now snap.amazon-ssm-agent.amazon-ssm-agent.service

# 1) Install essential tools
apt-get install -y git curl openssl jq

# 2) AWS CLI v2 (direct download, faster than snap)
if ! command -v aws &>/dev/null; then
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  cd /tmp && unzip -q awscliv2.zip && ./aws/install
  cd /
fi

# 3) Docker + compose
if ! command -v docker &>/dev/null; then
  apt-get install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable" > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  systemctl enable --now docker
fi

# 4) Caddy
if ! command -v caddy &>/dev/null; then
  apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -y
  apt-get install -y caddy
fi

# 5) Simple Caddyfile (no domain yet - serve on :80)
mkdir -p /etc/caddy
cat > /etc/caddy/Caddyfile <<'CADDYEOF'
:80 {
  reverse_proxy localhost:8000
}
CADDYEOF
systemctl enable caddy
systemctl restart caddy

# 6) Clone repo
APP_DIR="/opt/hyperlocal"
mkdir -p "$APP_DIR"
if [ ! -d "$APP_DIR/Backend" ]; then
  git clone --branch main https://github.com/Akasharyan47/hyperlocal_customer_app.git "$APP_DIR"
fi

# 7) Fetch DATABASE_URL from SSM and write .env
REGION="ap-south-1"
DB_URL="$(aws ssm get-parameter --name /hyperlocal/production/database_url --with-decryption --region $REGION --query Parameter.Value --output text 2>/dev/null)"
if [ -z "$DB_URL" ]; then
  echo "ERROR: Could not fetch DATABASE_URL from SSM!"
  exit 1
fi
echo "DATABASE_URL fetched OK"

DB_URL_SYNC="$(echo "$DB_URL" | sed 's/postgresql+asyncpg:/postgresql:/')"
JWT_KEY="$(openssl rand -hex 32)"
PAY_KEY="$(openssl rand -hex 32)"

cat > "$APP_DIR/Backend/.env" <<EOF
ENVIRONMENT=production
DATABASE_URL=$DB_URL
DATABASE_URL_SYNC=$DB_URL_SYNC
REDIS_URL=redis://redis:6379/0
CELERY_BROKER_URL=redis://redis:6379/1
CELERY_RESULT_BACKEND=redis://redis:6379/2
RATE_LIMIT_STORAGE_URI=redis://redis:3
OTP_STORAGE_URI=redis://redis:4
JWT_SECRET_KEY=$JWT_KEY
MOCK_PAYMENT_SECRET=$PAY_KEY
STORAGE_PROVIDER=s3
S3_BUCKET_NAME=hyperlocal-935173128886-uploads
S3_REGION=$REGION
OTP_DEV_MODE=false
OTP_MODE=live
RATE_LIMIT_ENABLED=true
SECURITY_HEADERS_ENABLED=true
LOG_LEVEL=INFO
LOG_FORMAT=json
TRUST_X_FORWARDED_FOR=true
EOF

# 8) Start the stack (api + worker + beat + redis + migrate)
cd "$APP_DIR/Backend"
docker compose -f docker-compose.cloud.yml up -d --build

echo "=== BOOT V2 COMPLETE $(date) ==="