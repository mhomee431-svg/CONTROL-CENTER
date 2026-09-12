# Hyperlocal Product Discovery Platform — Security

## Security Overview

This document describes the security measures implemented in the Hyperlocal Product Discovery Platform.

## Authentication

### JWT Tokens
- **Access Token**: Short-lived (30 minutes), used for API authentication
- **Refresh Token**: Long-lived (30 days), used to obtain new access tokens
- **Token Rotation**: Refresh tokens are rotated on each use
- **Reuse Detection**: Replayed refresh tokens revoke the session

### OTP Authentication
- **Customer**: Firebase Phone Auth (client-side OTP verification)
- **Shopkeeper**: Firebase Phone Auth (client-side verification)
- **Rate Limiting**: 5 OTP requests per minute per phone number
- **Attempt Limiting**: 5 verification attempts per OTP

### Password Security
- **Algorithm**: bcrypt with work factor 12 (2^12 iterations)
- **Salt**: Random salt generated per password
- **Comparison**: Constant-time comparison to prevent timing attacks

## Authorization

### Role-Based Access Control (RBAC)
- **Customer**: Can search products, save favorites, view shops
- **Shopkeeper**: Can manage own shops, inventory, prices
- **Admin**: Full platform management access

### Resource Ownership
- Shopkeepers can only access their own shops
- Customers can only modify their own data
- IDOR (Insecure Direct Object Reference) prevention via ownership checks

## API Security

### Rate Limiting
| Endpoint Type | Limit |
|---------------|-------|
| Default | 100 requests/minute |
| Authentication | 5 requests/minute |
| Search | 30 requests/minute |
| OTP | 5 requests/minute |

### CORS
- Configured per environment
- Production: Only allowed origins
- Development: localhost origins

### Security Headers
- Strict-Transport-Security (HSTS)
- X-Content-Type-Options
- X-Frame-Options
- X-XSS-Protection
- Content-Security-Policy

## Data Protection

### Encryption
- **In Transit**: TLS 1.3 (HTTPS only)
- **At Rest**: RDS storage encryption, S3 AES-256
- **Sensitive Data**: Passwords hashed, OTPs hashed

### Sensitive Data Handling
- OTPs are never logged or returned in production
- JWT secrets are never exposed
- Database credentials use SSM SecureString
- AWS credentials use IAM roles (no static keys)

## Infrastructure Security

### Network
- VPC with public/private subnets
- RDS in private subnet (no public access)
- Security groups restrict traffic
- VPC Flow Logs for audit

### Compute
- EC2 with IMDSv2 required
- Root volume encrypted
- No SSH port (Session Manager only)
- Instance role with least privilege

### S3
- All public access blocked
- TLS-only bucket policy
- Server-side encryption (AES-256)
- Lifecycle policies for cleanup

## Secrets Management

### Development
- `.env` file (never committed)
- `.env.example` for reference

### Production
- AWS SSM Parameter Store (SecureString)
- Secrets injected at boot via user_data
- No secrets in source code or container images

## Security Checklist

- [ ] All secrets rotated and removed from git
- [ ] bcrypt password hashing implemented
- [ ] Rate limiting enabled
- [ ] CORS configured
- [ ] Security headers enabled
- [ ] HTTPS enforced
- [ ] Database not publicly accessible
- [ ] S3 bucket private
- [ ] IAM roles follow least privilege
- [ ] VPC Flow Logs enabled
- [ ] Automated backups enabled
- [ ] Security scanning in CI/CD
