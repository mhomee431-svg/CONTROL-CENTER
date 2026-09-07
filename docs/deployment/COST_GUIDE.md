# Hyperlocal Product Discovery Platform — Cost Guide

## AWS Free Tier (First 12 Months)

| Service | Free Tier Allowance | Usage | Cost |
|---------|---------------------|-------|------|
| EC2 t3.micro | 750 hours/month | 750 hours | $0 |
| EBS gp2 | 30 GB/month | 20 GB | $0 |
| Elastic IP | Attached to running instance | 1 | $0 |
| RDS db.t3.micro | 750 hours/month | 750 hours | $0 |
| RDS Storage | 20 GB | 20 GB | $0 |
| S3 | 5 GB + 20k GET + 2k PUT | < 5 GB | $0 |
| SSM Parameters | Unlimited | < 100 | $0 |
| VPC Flow Logs | 10 GB/month | < 10 GB | $0 |
| **Total** | | | **$0/month** |

## Post Free Tier (13+ Months)

| Service | Estimated Monthly Cost |
|---------|----------------------|
| EC2 t3.micro | ~$7.60 |
| EBS 20 GB gp2 | ~$1.60 |
| Elastic IP | $0 (attached) |
| RDS db.t3.micro | ~$12.50 |
| RDS Storage 20 GB | ~$2.50 |
| S3 5 GB | ~$0.12 |
| CloudWatch Logs | ~$1.00 |
| **Total** | **~$25/month** |

## Cost Optimization Strategies

### Compute
- Use t3.micro burstable instances
- Monitor CPU credits
- Use Spot Instances for non-critical workloads (future)

### Database
- Use db.t3.micro for < 100k products
- Enable auto-pause for dev/staging
- Monitor storage growth
- Use read replicas only when needed

### Storage
- S3 lifecycle policies for old objects
- Compress images before upload
- Use S3 Intelligent-Tiering (future)

### Network
- Use S3 Gateway Endpoint (free)
- Minimize data transfer between regions
- Use CloudFront for static assets (future)

## Scaling Cost Estimates

### Stage A (Current) — $0-25/month
- Single EC2 t3.micro
- Single RDS db.t3.micro
- Local Redis container

### Stage B (Growth) — $100-300/month
- ECS Fargate (2-4 tasks)
- RDS db.t3.small
- ElastiCache cache.t3.micro
- ALB
- CloudFront

### Stage C (Scale) — $500+/month
- ECS Fargate (8+ tasks)
- RDS db.t3.medium with read replicas
- ElastiCache cache.t3.small
- OpenSearch (if needed)
- WAF

## Monitoring Costs

### AWS Cost Explorer
- Enable cost allocation tags
- Set up billing alerts
- Review monthly

### Cost Allocation Tags
| Tag | Value |
|-----|-------|
| Project | Hyperlocal |
| Environment | production/staging/dev |
| ManagedBy | Terraform |

### Budget Alerts
| Threshold | Action |
|-----------|--------|
| $10/month | Warning |
| $25/month | Alert |
| $50/month | Critical |

## Free Tier Expiration Tracking

| Service | Free Tier Ends | Action Required |
|---------|----------------|-----------------|
| EC2 | 12 months from signup | Upgrade or accept charges |
| RDS | 12 months from signup | Upgrade or accept charges |
| EBS | 12 months from signup | Upgrade or accept charges |
| S3 | 12 months from signup | Upgrade or accept charges |

## Cost-Saving Recommendations

1. **Use Reserved Instances** for predictable workloads (save up to 30%)
2. **Use Savings Plans** for flexible commitment
3. **Delete unused resources** (old snapshots, unused EIPs)
4. **Right-size instances** based on actual usage
5. **Use auto-scaling** to match demand
