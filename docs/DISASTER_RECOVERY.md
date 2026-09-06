# Hyperlocal Product Discovery Platform — Disaster Recovery

## Recovery Objectives

| Metric | Target |
|--------|--------|
| RPO (Recovery Point Objective) | 1 hour |
| RTO (Recovery Time Objective) | 4 hours |

## Backup Strategy

### Database (RDS)
- **Automated Backups**: 7-day retention
- **Point-in-Time Recovery**: Available within retention window
- **Manual Snapshots**: Before major changes
- **Final Snapshot**: On destroy

### S3 (Object Storage)
- **Versioning**: Disabled (cost optimization)
- **Lifecycle Policies**: Cleanup incomplete uploads
- **Cross-Region Replication**: Not enabled (Stage A)

### Application
- **Container Images**: Stored in ECR (immutable tags)
- **Infrastructure**: Terraform state
- **Configuration**: SSM Parameter Store

## Recovery Procedures

### Database Recovery

#### Point-in-Time Recovery
```powershell
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier hyperlocal-production-db \
  --target-db-instance-identifier hyperlocal-recovered-db \
  --restore-time "2024-01-01T00:00:00Z"
```

#### Snapshot Restore
```powershell
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier hyperlocal-recovered-db \
  --db-snapshot-identifier <snapshot-id>
```

### Application Recovery

#### Redeploy from ECR
```powershell
# 1. Get previous image
aws ecr describe-images --repository-name hyperlocal-backend

# 2. Deploy previous image
./infra/scripts/cicd_rollback.sh --target compose \
  --region ap-south-1 \
  --instance-tag hyperlocal-production-app \
  --image <previous-image-uri>
```

#### Full Infrastructure Recreation
```powershell
# 1. Destroy current infrastructure
terraform destroy

# 2. Rebuild from Terraform
terraform apply

# 3. Restore database from snapshot
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier hyperlocal-production-db \
  --db-snapshot-identifier <latest-snapshot>
```

### S3 Recovery

#### Object Recovery
```powershell
# If versioning was enabled:
aws s3api list-object-versions --bucket hyperlocal-uploads --prefix <key>
aws s3api get-object --bucket hyperlocal-uploads --key <key> --version-id <version-id> <output-file>
```

## Disaster Scenarios

### Scenario 1: Database Failure
1. Detect failure via CloudWatch alarms
2. Initiate point-in-time recovery
3. Update DATABASE_URL in SSM
4. Restart application
5. Verify data integrity

### Scenario 2: EC2 Instance Failure
1. Detect failure via health checks
2. Launch new instance from AMI
3. Attach to same security group
4. Reassign Elastic IP
5. Start Docker Compose
6. Verify health

### Scenario 3: Complete Region Failure
1. Switch to backup region (if configured)
2. Restore database from cross-region snapshot
3. Redeploy infrastructure via Terraform
4. Update DNS to point to new region
5. Verify all services

### Scenario 4: Data Corruption
1. Identify corruption point
2. Restore from last known good snapshot
3. Replay transactions if possible
4. Verify data integrity
5. Resume operations

## Testing

### Monthly Recovery Drill
1. Restore database to test instance
2. Verify data integrity
3. Run application against test database
4. Document results
5. Update procedures if needed

### Quarterly Full DR Test
1. Simulate complete region failure
2. Execute full recovery procedure
3. Measure RTO and RPO
4. Document lessons learned
5. Update DR plan

## Contact Information

| Role | Contact |
|------|---------|
| On-Call Engineer | [TBD] |
| AWS Support | https://aws.amazon.com/support |
| Database Admin | [TBD] |
