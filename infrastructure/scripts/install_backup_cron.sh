#!/usr/bin/env bash
# infrastructure/scripts/install_backup_cron.sh — Install scheduled logical backups (Phase 5).
#
# Registers a systemd timer that runs backup_db.sh DAILY (full logical dump +
# manifest + optional S3 DR copy). This makes backups AUTOMATED on any host,
# independent of the RDS-native automated snapshots (which are the other layer).
#
# Usage (run as root / sudo on the EC2 or any PostgreSQL host):
#   sudo ./install_backup_cron.sh <environment> \
#       --database-url 'postgresql+asyncpg://...' \
#       [--backup-bucket s3://<bucket>/<prefix>] \
#       [--backup-dir /var/backups/hyperlocal] \
#       [--retention-days 7]
#   systemctl list-timers hyperlocal-db-backup.timer   # confirm next run
#
# Idempotent: re-running refreshes the service/timer definitions.
set -euo pipefail

ENV_NAME="${1:?usage: install_backup_cron.sh <environment> [--database-url <url>] [--backup-bucket s3://...]}"
shift
DATABASE_URL=""
BACKUP_BUCKET=""
BACKUP_DIR="/var/backups/hyperlocal"
RETENTION_DAYS=7
PROJECT="${PROJECT_NAME:-hyperlocal}"

while [ $# -gt 0 ]; do
  case "$1" in
    --database-url) DATABASE_URL="$2"; shift 2 ;;
    --backup-bucket) BACKUP_BUCKET="$2"; shift 2 ;;
    --backup-dir) BACKUP_DIR="$2"; shift 2 ;;
    --retention-days) RETENTION_DAYS="$2"; shift 2 ;;
    *) echo "!! unknown argument: $1"; exit 2 ;;
  esac
done

[ "$(id -u)" = "0" ] || echo "Warning: not root — systemd install will likely fail; use sudo."
: "${DATABASE_URL:?--database-url is required (or set DATABASE_URL in this shell)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SH="${SCRIPT_DIR}/backup_db.sh"

# ── 1. Ensure the backup directory exists ──────────────────────────────────────
mkdir -p "$BACKUP_DIR"

# ── 2. systemd service (the actual backup job) ────────────────────────────────
cat > /etc/systemd/system/hyperlocal-db-backup.service <<EOF
[Unit]
Description=Hyperlocal PostgreSQL logical backup (project=${PROJECT}, env=${ENV_NAME})
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
Environment=DATABASE_URL=${DATABASE_URL}
Environment=BACKUP_DIR=${BACKUP_DIR}
Environment=RETENTION_DAYS=${RETENTION_DAYS}
Environment=PROJECT_NAME=${PROJECT}
$( [ -n "$BACKUP_BUCKET" ] && echo "Environment=BACKUP_BUCKET=${BACKUP_BUCKET}" )
ExecStart=${BACKUP_SH} ${ENV_NAME} --mode dump
EOF

# ── 3. systemd timer (schedule: 02:30 UTC daily + on-boot catch-up) ───────────
cat > /etc/systemd/system/hyperlocal-db-backup.timer <<EOF
[Unit]
Description=Run Hyperlocal DB backup daily at 02:30 UTC
Requires=hyperlocal-db-backup.service

[Timer]
OnCalendar=*-*-* 02:30:00 UTC
RandomizedDelaySec=300
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now hyperlocal-db-backup.timer
systemctl restart hyperlocal-db-backup.timer

echo "✅ installed:"
systemctl status hyperlocal-db-backup.timer --no-pager | head -5 || true
echo "  next run:  $(systemctl show hyperlocal-db-backup.timer -p NextElapseOnRealTime --value)"
echo "  manual:    systemctl start hyperlocal-db-backup.service"