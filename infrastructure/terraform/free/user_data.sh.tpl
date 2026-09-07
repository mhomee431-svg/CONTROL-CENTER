#!/bin/bash
# infrastructure/terraform/free/user_data.sh.tpl -- rendered by Terraform as EC2 user_data.
#
# Idempotent boot script:
#   1. install Docker + compose plugin
#   2. add swap (t3.micro has 2GB RAM; image builds need headroom)
#   3. clone/pull the repo using an optional GitHub PAT from SSM
#   4. generate backend/.env ONCE (random JWT secret persisted outside repo)
#   5. docker compose -f docker-compose.free.yml up -d --build
#
# Runs at first boot; if the clone failed because the PAT was missing, just
# REBOOT the instance from the console and this script finishes the job.
#
# NOTE: this file IS a Terraform template. Only the assignments marked "TF:"
# are real interpolations; every other BASH variable is written with an
# escaped double-dollar ($${VAR}) on purpose so HCL leaves it alone.

set -euo pipefail

REGION="${region}"                                # TF: region
PARAM_NAME="/${project}/free/github_token"        # TF: project
BRANCH="${branch}"                                # TF: branch
REPO_URL="${repo_url}"                            # TF: repo
APP_DIR="${app_dir}"                              # TF: app_dir

export DEBIAN_FRONTEND=noninteractive

log() { echo "[hyperlocal-boot] $*" | systemd-cat -t hyperlocal-boot -p info; }

# 1. Docker + git (idempotent)
if ! command -v docker >/dev/null 2>&1; then
  log "installing docker"
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg git openssl
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
systemctl enable --now docker

# 2. Swap 2G (once)
if ! swapon --show=NAME | grep -q '/swapfile'; then
  log "creating 2G swapfile"
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# 3. Clone/pull (PAT optional while the repository stays public)
TOKEN="$(aws ssm get-parameter --region "$REGION" --name "$PARAM_NAME" \
  --with-decryption --query Parameter.Value --output text 2>/dev/null || echo PLACEHOLDER)"
AUTH_PART=""
if [ -n "$TOKEN" ] && [ "$TOKEN" != "PLACEHOLDER_REPLACE_WITH_GITHUB_PAT" ]; then
  AUTH_PART="x-access-token:$${TOKEN}@"           # $${...} = literal bash var
  log "using GitHub PAT from SSM"
else
  log "no PAT configured (public-repo path)"
fi

mkdir -p "$APP_DIR"
cd "$APP_DIR"
if [ -d app/.git ]; then
  cd app && git fetch origin "$BRANCH" && git reset --hard "origin/$BRANCH"
else
  rm -rf app
  git clone --branch "$BRANCH" "https://$${AUTH_PART}$${REPO_URL#https://}" app
fi

# 4. One-time .env generation OUTSIDE the repo, copied into place every boot.
SECRETS_DIR="$APP_DIR/secrets"
mkdir -p "$SECRETS_DIR"
if [ ! -f "$SECRETS_DIR/.env" ]; then
  log "generating fresh backend/.env (random JWT secret)"
  JWT_SECRET="$(openssl rand -hex 32)"
  PAY_SECRET="$(openssl rand -hex 32)"
  cat > "$SECRETS_DIR/.env" <<ENV
ENVIRONMENT=staging
DEBUG=false
LOG_FORMAT=console
JWT_SECRET_KEY=$${JWT_SECRET}
MOCK_PAYMENT_SECRET=$${PAY_SECRET}
OTP_DEV_MODE=true
OTP_DEV_VALUE=123456
SMS_PROVIDER=mock
EMAIL_PROVIDER=mock
STORAGE_PROVIDER=local
RATE_LIMIT_STORAGE_URI=redis://redis:6379/3
FRONTEND_URL=http://localhost:3000
CORS_ORIGINS=http://localhost:3000
ENV
  chmod 600 "$SECRETS_DIR/.env"
fi
cp "$SECRETS_DIR/.env" "$APP_DIR/app/backend/.env"

# 5. Build & start
cd "$APP_DIR/app/backend"
docker compose -f docker-compose.free.yml up -d --build || \
  log "compose failed this boot - fix and reboot the instance to retry"

log "bootstrap pass complete"
