# Hyperlocal Product Discovery Platform — Environment Configuration

> **Branch vs environment:** branches (`develop`, `main`) decide *which code* is
> released; environments (`staging`, `production`) decide *where* it runs.
> The full mapping, gates and runbooks live in
> [`BRANCHING.md`](BRANCHING.md).

## Environments

### Local Development
- **Branch**: any `feature/*` (local run, no deployment)
- **Backend**: `http://localhost:8000`
- **Database**: Local PostgreSQL + PostGIS (Docker)
- **Redis**: Local Redis (Docker)
- **Storage**: Local filesystem

### Staging
- **Branch**: `develop` — deployed automatically on every push
- **Backend**: `https://staging-api.hyperlocal.in`
- **Database**: RDS PostgreSQL (staging instance)
- **Redis**: Local container on EC2
- **Storage**: S3 staging bucket
- **Secrets**: SSM `/hyperlocal/staging/*`

### Production
- **Branch**: `main` — deployed automatically after approval on the protected
  `production` environment
- **Backend**: `https://api.hyperlocal.in`
- **Database**: RDS PostgreSQL (production instance)
- **Redis**: Local container on EC2
- **Storage**: S3 production bucket
- **Secrets**: SSM `/hyperlocal/production/*`

## Environment Variables

### Core Settings

| Variable | Development | Staging | Production |
|----------|-------------|---------|------------|
| ENVIRONMENT | development | staging | production |
| DEBUG | true | false | false |
| API_PREFIX | /api/v1 | /api/v1 | /api/v1 |
| LOG_LEVEL | DEBUG | INFO | WARNING |

### Database

| Variable | Description |
|----------|-------------|
| DATABASE_URL | Async PostgreSQL URL (asyncpg) |
| DATABASE_POOL_SIZE | Connection pool size (default: 20) |
| DATABASE_MAX_OVERFLOW | Max overflow connections (default: 40) |
| POSTGIS_EXTENSION | PostGIS extension name |

### Redis

| Variable | Description |
|----------|-------------|
| REDIS_URL | Redis connection URL |
| CELERY_BROKER_URL | Celery broker URL |
| CELERY_RESULT_BACKEND | Celery result backend URL |
| CACHE_DEFAULT_TTL | Default cache TTL in seconds |

### Security

| Variable | Description |
|----------|-------------|
| JWT_SECRET_KEY | JWT signing secret (32+ chars) |
| JWT_ALGORITHM | JWT algorithm (HS256) |
| ACCESS_TOKEN_EXPIRE_MINUTES | Access token lifetime |
| REFRESH_TOKEN_EXPIRE_DAYS | Refresh token lifetime |
| OTP_MODE | OTP delivery mode (mock/live) |

### Storage

| Variable | Description |
|----------|-------------|
| STORAGE_PROVIDER | Storage provider (local/s3/cloudinary) |
| S3_BUCKET_NAME | S3 bucket name |
| S3_REGION | AWS region for S3 |

### CORS

| Variable | Description |
|----------|-------------|
| CORS_ORIGINS | Comma-separated allowed origins |

## Flutter App Environments

### Customer App (Frontend)

| Environment | Base URL |
|-------------|----------|
| Development | `http://localhost:8000` |
| Staging | `https://staging-api.hyperlocal.in` |
| Production | `https://api.hyperlocal.in` |

**Build Configuration:**
```bash
# Development (default)
flutter run

# Staging
flutter run --dart-define=APP_ENV=staging

# Production
flutter build apk --release --dart-define=API_BASE_URL=https://api.hyperlocal.in
```

### Shopkeeper App

| Environment | Base URL |
|-------------|----------|
| Development | `http://10.0.2.2:8000` (Android emulator) |
| Staging | `https://staging-api.hyperlocal.in` |
| Production | `https://api.hyperlocal.in` |

**Build Configuration:**
```bash
# Development (default)
flutter run

# Staging
flutter run --dart-define=APP_ENV=staging

# Production
flutter build apk --release --dart-define=SHOPKEEPER_API_BASE_URL=https://api.hyperlocal.in
```

## Secrets Management

### Development
- Use `.env` file (never committed)
- Copy from `.env.example` and fill in values

### Production
- AWS SSM Parameter Store (SecureString)
- Secrets injected at boot via user_data script
- No secrets in source code or container images

### SSM Parameter Paths
```
/hyperlocal/<environment>/database_url
/hyperlocal/<environment>/jwt_secret
/hyperlocal/<environment>/github_token
```

## Feature Flags

| Flag | Description | Default |
|------|-------------|---------|
| RATE_LIMIT_ENABLED | Enable rate limiting | true |
| SECURITY_HEADERS_ENABLED | Enable security headers | true |
| OTP_DEV_MODE | Return OTP in response | false (dev only) |
| FCM_DRY_RUN | FCM dry run mode | false |
