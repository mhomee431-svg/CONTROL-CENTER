# ── Redis — FREE-TIER note ───────────────────────────────────────────────────
# ElastiCache is a PAID service with no free tier. On the free-tier topology
# Redis runs as a local Docker container on the app instance (started by
# user_data.sh.tpl, bound to 127.0.0.1:6379 — never reachable from outside
# the host, which satisfies the "Redis must not be publicly exposed" rule).
#
# The backend connects with:  REDIS_URL=redis://127.0.0.1:6379/0
#
# Upgrade path (when budget allows): recreate the old ElastiCache + NAT/ALB
# module from git history (infrastructure/terraform before the Phase-3 free-tier
# refactor) or infrastructure/free's compose design.
