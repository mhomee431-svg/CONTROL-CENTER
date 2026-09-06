# Hyperlocal Product Discovery Platform — Runbook

## Common Operations

### Deploy Application

```powershell
# 1. Push to main (triggers CI/CD)
git push origin main

# 2. Monitor deployment
# GitHub Actions → Backend CD workflow

# 3. Verify health
curl https://api.hyperlocal.in/health
curl https://api.hyperlocal.in/ready
```

### Rollback Application

```powershell
# Automatic rollback on failure
# Or manual rollback:
./infra/scripts/cicd_rollback.sh --target compose `
  --region ap-south-1 `
  --instance-tag hyperlocal-production-app `
  --image <previous-image-uri>
```

### Database Migration

```powershell
# Migrations run automatically on deploy
# Manual migration:
aws ssm send-command --document-name "AWS-RunShellScript" `
  --targets "Key=tag:Name,Values=hyperlocal-production-app" `
  --parameters 'commands=["cd /opt/hyperlocal && docker compose run --rm migrate"]'
```

### Database Backup

```powershell
# Automated backups are configured
# Manual snapshot:
aws rds create-db-snapshot \
  --db-instance-identifier hyperlocal-production-db \
  --db-snapshot-identifier manual-$(date +%Y%m%d%H%M%S)
```

### Database Restore

```powershell
# Point-in-time recovery:
./infra/scripts/rds_restore.sh \
  --source-db hyperlocal-production-db \
  --target-db hyperlocal-restored-db \
  --time "2024-01-01T00:00:00Z"
```

## Troubleshooting

### Application Not Responding

1. Check EC2 instance status
```powershell
aws ec2 describe-instances --filters "Name=tag:Name,Values=hyperlocal-production-app"
```

2. Connect via Session Manager
```powershell
aws ssm start-session --target <instance-id>
```

3. Check Docker containers
```bash
docker ps
docker logs hyperlocal-cloud-api-1
```

4. Check Caddy
```bash
systemctl status caddy
journalctl -u caddy -f
```

### Database Connection Issues

1. Check RDS status
```powershell
aws rds describe-db-instances --db-instance-identifier hyperlocal-production-db
```

2. Check security groups
```powershell
aws ec2 describe-security-groups --group-ids <sg-id>
```

3. Test connectivity from EC2
```bash
psql -h <rds-endpoint> -U hyperlocal -d hyperlocal
```

### High CPU/Memory

1. Check CloudWatch metrics
2. Scale up instance if needed
3. Check for slow queries:
```sql
SELECT * FROM pg_stat_activity WHERE state = 'active';
SELECT * FROM pg_stat_statements ORDER BY total_time DESC LIMIT 10;
```

### Redis Issues

1. Check Redis container
```bash
docker exec -it hyperlocal-cloud-redis-1 redis-cli ping
```

2. Check memory usage
```bash
docker exec -it hyperlocal-cloud-redis-1 redis-cli info memory
```

3. Restart Redis
```bash
docker compose restart redis
```

## Monitoring

### Health Checks
- `/health` — Should return 200 OK
- `/ready` — Should return 200 OK (checks DB, Redis, PostGIS)

### Key Metrics
- API response time (p95 < 300ms)
- Error rate (5xx < 1%)
- Database connections (< 80% of max)
- CPU utilization (< 80%)

### Alarms
- API 5xx rate > 1%
- Database connections > 80%
- CPU > 80% for 5 minutes

## Emergency Contacts

- AWS Support: https://aws.amazon.com/support
- GitHub Security: security@github.com
