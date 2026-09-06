# Hyperlocal Product Discovery Platform — AWS Architecture

## Region

**Primary Region**: `ap-south-1` (Mumbai, India)

Selected for:
- Low latency for Indian users
- Free Tier availability
- Service availability

## VPC Configuration

```
VPC: 10.0.0.0/16
├── Public Subnet (App): 10.0.1.0/24 (AZ a)
│   └── EC2 t3.micro (Caddy + Docker)
└── Data Subnet (RDS): 10.0.20.0/24 (AZ b)
    └── RDS PostgreSQL 16 + PostGIS
```

## Security Groups

### App Security Group
| Direction | Port | Source | Description |
|-----------|------|--------|-------------|
| Inbound | 80 | 0.0.0.0/0 | HTTP (Caddy) |
| Inbound | 443 | 0.0.0.0/0 | HTTPS (Caddy) |
| Outbound | All | 0.0.0.0/0 | All traffic |

### RDS Security Group
| Direction | Port | Source | Description |
|-----------|------|--------|-------------|
| Inbound | 5432 | App SG | PostgreSQL from app only |
| Outbound | - | - | None (RDS doesn't initiate) |

## EC2 Instance

### Configuration
- **Instance Type**: t3.micro (2 vCPU, 1 GB RAM)
- **AMI**: Ubuntu 24.04 LTS (Noble)
- **Root Volume**: 20 GB gp2 (encrypted)
- **IMDS**: v2 required

### Instance Role
- SSM Managed Instance Core (Session Manager)
- SSM Parameter Read (own path only)
- S3 Read/Write (uploads bucket only)

### Boot Sequence
1. Install Docker & Docker Compose
2. Install & configure Caddy
3. Clone repository
4. Fetch secrets from SSM
5. Start Docker Compose stack
6. Run health check

## RDS PostgreSQL

### Configuration
- **Engine**: PostgreSQL 16.15
- **Instance Class**: db.t3.micro
- **Storage**: 20 GB gp2 (encrypted)
- **Multi-AZ**: No (cost optimization)
- **Publicly Accessible**: No

### Backups
- **Automated Backups**: 7-day retention
- **Backup Window**: 03:00-03:30 UTC
- **Point-in-Time Recovery**: Enabled
- **Final Snapshot**: On destroy

### PostGIS
```sql
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
```

## S3 Bucket

### Configuration
- **Bucket Name**: hyperlocal-<account-id>-uploads
- **Versioning**: Disabled (cost optimization)
- **Encryption**: AES-256 (SSE-S3)
- **Public Access**: Blocked (all 4 settings)

### Bucket Policy
```json
{
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:*",
  "Resource": ["arn:aws:s3:::bucket/*"],
  "Condition": {
    "Bool": {"aws:SecureTransport": "false"}
  }
}
```

### Lifecycle Rules
- Abort incomplete multipart uploads after 7 days

## Redis (Local Container)

Redis runs as a local Docker container on the EC2 instance:
- **Image**: redis:7-alpine
- **Port**: 127.0.0.1:6379 (not exposed to host)
- **Persistence**: AOF (append-only file)

### Database Allocation
| DB | Purpose |
|----|---------|
| 0 | Cache |
| 1 | Celery Broker |
| 2 | Celery Results |
| 3 | Rate Limiting |
| 4 | OTP Storage |

## Route53 (Optional)

If domain is managed in AWS:
- **A Record**: api.hyperlocal.in → EIP
- **TTL**: 300 seconds

## CloudWatch

### VPC Flow Logs
- **Retention**: 14 days
- **Destination**: CloudWatch Logs

### Application Logs
- Docker logs via CloudWatch agent (future)

## Cost Optimization

| Service | Free Tier | Monthly Cost |
|---------|-----------|--------------|
| EC2 t3.micro | 750 hours | $0 |
| RDS db.t3.micro | 750 hours | $0 |
| EBS 20GB | 30 GB | $0 |
| Elastic IP | Attached | $0 |
| S3 5GB | 5 GB | $0 |
| SSM Parameters | Unlimited | $0 |
| VPC Flow Logs | 14 days | $0 |
| **Total** | | **$0** |

## Upgrade Path (Stage B)

1. **Compute**: EC2 → ECS Fargate
2. **Cache**: Local Redis → ElastiCache
3. **Load Balancer**: Caddy → ALB
4. **CDN**: Add CloudFront
5. **Security**: Add WAF
6. **Search**: Add OpenSearch (if needed)
