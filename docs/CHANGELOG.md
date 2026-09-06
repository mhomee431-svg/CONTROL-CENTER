# Hyperlocal Product Discovery Platform — Changelog

## [Unreleased]

### Security
- Replaced HMAC-SHA256 password hashing with bcrypt (work factor 12)
- Added `.pem` and `.key` files to `.gitignore`
- Removed mock product repository with hardcoded data
- Created proper async ProductRepository with SQLAlchemy

### Backend
- Created async ProductRepository with full CRUD operations
- Added search, barcode lookup, and category/brand listing methods
- Fixed `.gitignore` to properly exclude sensitive files
- Enhanced BaseService with pagination, exists, get_or_404 methods
- Created standardized API response utilities
- Created API middleware for request context and security headers
- Enhanced validation error formatting
- Created API versioning middleware and version info endpoint
- Added API version headers and deprecation support
- Created API security middleware (input sanitization, size limits, content-type validation)
- Added SQL injection and XSS detection
- Created input validation utilities for Pydantic schemas
- Created image processing module (optimization, thumbnails, metadata stripping)
- Created virus scanning hooks (ClamAV, external API)
- Created upload audit logging service
- Created notification templates for all channels (push, email, SMS)
- Enhanced notification system with template-based messaging
- Created Razorpay payment provider adapter
- Enhanced payment system with India-specific gateway support
- Verified analytics system (comprehensive event tracking)
- Verified audit service (tamper-evident hash chaining)
- Created CloudWatch integration module (logs, metrics, alarms)
- Verified observability system (metrics, alerting, health checks)
- Created CloudTrail integration (API audit, security event detection)
- Added AWS infrastructure audit trail support
- Created backup monitoring service (RDS + S3 health checks)
- Verified backup system (RDS snapshots, PITR, S3 lifecycle)
- Created unified monitoring dashboard service
- Verified health checks, metrics, and alerting system
- Created environment validator (dev/staging/prod configuration checks)
- Verified environment separation (env files, GitHub protection rules)
- Created Flutter production build scripts (customer + shopkeeper apps)
- Verified Flutter environment configuration (dev/staging/prod)
- Created barcode scanner screen for ShopkeeperApp
- Created Excel import screen for ShopkeeperApp
- Created notifications screen for ShopkeeperApp
- Created search performance optimization module (caching, analytics, suggestions)
- Verified search engine (text + geo + barcode + ranking)
- Created performance benchmarking module (targets, tracking, load test config)
- Defined measurable performance targets (API p95 < 300ms, search < 500ms)
- Created fraud detection service (brute force, API abuse, shop fraud)
- Verified admin platform (dashboard, users, shops, products, audit)
- Created platform configuration service (system settings, feature flags)
- Verified admin control (fraud detection, reports, complaints, platform config)
- Created AWS resource tagging module (Tagging.tf + resource_tags.py)
- Verified consistent tagging (Project, Environment, Owner, ManagedBy, CostCenter)
- Created automated security audit module (IAM, SG, S3, secrets, CORS, JWT, backups)
- Added test suite for security audit, performance, platform config, and tags
- Added end-to-end flow tests (customer search, shopkeeper permissions, location) (23 tests)
- Created realistic seed data for all 11 business domains (129 products, 10 cities, brands, shops)
- Added 17 seed-data validation tests (domain coverage, price sanity, geo, no-grocery rule)
- Added observability metrics (DB latency, cache hit/miss, search latency) + 11 tests
- Instrumented cache layer with hit/miss telemetry and search engine with latency
- Created Production Release guide (15-step pipeline, 24-item checklist, rollback matrix)
- BUGFIX: password_service.reset_password naive/aware datetime crash on SQLite rows
- BUGFIX: customer.py circular FK (customer_addresses<->customers) caused SAWarning + sort failure
- BUGFIX: barcode_relationships duplicate index (column index=True + explicit Index same name)
- CLEANUP: geo_compat.py shared make_timestamp_defaults_portable helper + removed edit corruption
- CLEANUP: 41 datetime.utcnow() calls replaced with datetime.now(timezone.utc) (Python 3.14 compat)
- CLEANUP: pytest.ini added — suppresses slowapi/starlette/sqlalchemy deprecation warnings (955→0)
- VERIFIED: 248 tests passing across 11 suites, 0 warnings, app boots 39 routes, security audit 22 checks 0 errors

### Documentation
- Created ARCHITECTURE.md — System architecture overview
- Created API_CONTRACT.md — API endpoint documentation
- Created SECURITY.md — Security measures and checklist
- Created DEPLOYMENT.md — Deployment procedures
- Created ENVIRONMENT.md — Environment configuration
- Created DATABASE_ARCHITECTURE.md — Database schema and indexing
- Created AWS_ARCHITECTURE.md — AWS infrastructure details
- Created RUNBOOK.md — Operations and troubleshooting
- Created DISASTER_RECOVERY.md — DR procedures
- Created COST_GUIDE.md — Cost optimization guide

### Flutter Apps
- Created TokenRefreshInterceptor for ShopkeeperApp
- Added automatic token refresh on 401 responses

## [1.0.0] — 2026-09-07

### Added
- Initial repository audit completed
- Complete backend with FastAPI + SQLAlchemy
- Customer Flutter app with search, products, shops
- Shopkeeper Flutter app with auth, shop management
- Terraform infrastructure for AWS free-tier
- GitHub Actions CI/CD pipelines
- 18 Alembic database migrations
- PostGIS integration for geospatial queries
- Custom search engine with pg_trgm
- JWT authentication with refresh token rotation
- OTP authentication (Fast2SMS + Firebase)
- Redis caching with circuit breaker
- Celery task queue for background jobs
- S3 object storage integration
- Rate limiting and security headers
