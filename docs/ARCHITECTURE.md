# Hyperlocal Product Discovery Platform — Architecture

## Overview

Hyperlocal Product Discovery Platform enables customers to search any product and instantly discover which nearby shop has it, at what price, and how far it is. This is primarily an **offline discovery platform** — customers discover products and visit physical shops to purchase.

## Core Business Domains

1. Pharmacy & Healthcare
2. Beauty & Personal Care
3. Furniture & Home Care
4. Household Goods
5. Sports, Fitness & Outdoor
6. Books, Media & Stationery
7. Automotive Parts & Tools
8. Hardware
9. Restaurants (discovery only)
10. Transport
11. Personal Transport & Travel

## System Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Customer App   │     │ Shopkeeper App  │     │   Admin Panel   │
│    (Flutter)    │     │    (Flutter)    │     │    (Future)     │
└────────┬────────┘     └────────┬────────┘     └────────┬────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │ HTTPS REST API
                                 ▼
                    ┌─────────────────────────┐
                    │     FastAPI Backend      │
                    │   (Modular Monolith)     │
                    └────────────┬────────────┘
                                 │
              ┌──────────────────┼──────────────────┐
              │                  │                  │
              ▼                  ▼                  ▼
    ┌─────────────────┐ ┌─────────────┐ ┌─────────────────┐
    │   PostgreSQL    │ │    Redis    │ │       S3        │
    │   + PostGIS     │ │   (Cache)   │ │  (Object Store) │
    └─────────────────┘ └─────────────┘ └─────────────────┘
```

## Technology Stack

| Layer | Technology | Version |
|-------|-----------|---------|
| Customer App | Flutter | 3.13+ |
| Shopkeeper App | Flutter | 3.13+ |
| Backend | FastAPI + Python | 3.14 |
| ORM | SQLAlchemy | 2.0+ |
| Database | PostgreSQL | 16 |
| Geospatial | PostGIS | 3.4 |
| Cache | Redis | 7 |
| Task Queue | Celery | 5.4+ |
| Object Storage | AWS S3 | - |
| Infrastructure | Terraform | - |
| CI/CD | GitHub Actions | - |

## Backend Module Structure

```
Backend/
├── app/
│   ├── api/routes/          # API endpoint handlers
│   │   ├── auth.py          # Customer authentication
│   │   ├── shopkeeper_auth.py # Shopkeeper authentication
│   │   ├── search.py        # Product discovery
│   │   ├── products.py      # Product catalog
│   │   ├── shops.py         # Shop management
│   │   ├── inventory.py     # Inventory management
│   │   ├── locations.py     # Location services
│   │   ├── media.py         # S3 media uploads
│   │   ├── admin.py         # Admin operations
│   │   └── ...
│   ├── core/                # Core infrastructure
│   │   ├── config.py        # Settings management
│   │   ├── security.py      # JWT + password hashing
│   │   ├── dependencies.py  # FastAPI DI
│   │   ├── cache.py         # Redis cache
│   │   └── ...
│   ├── models/              # SQLAlchemy ORM models
│   ├── schemas/             # Pydantic request/response schemas
│   ├── services/            # Business logic services
│   ├── repositories/        # Data access layer
│   ├── search/              # Search engine
│   └── database/            # Database session management
├── alembic/                 # Database migrations
├── tests/                   # Test suite
└── Dockerfile               # Production container
```

## Data Flow

### Customer Search Flow
1. Customer opens app → grants location permission
2. App sends search query + coordinates to `/api/v1/search/v2/products`
3. Backend queries PostGIS for nearby shops with matching products
4. Results sorted by relevance, distance, price, or rating
5. Customer views results → taps shop → gets directions

### Shopkeeper Inventory Flow
1. Shopkeeper logs in via OTP/Firebase
2. Creates business → captures location via GPS
3. Adds products via barcode scan, manual entry, or Excel import
4. Sets prices and inventory levels
5. Products become discoverable to nearby customers

## Security Architecture

- **Authentication**: JWT (HS256) with refresh token rotation
- **OTP**: Fast2SMS (customer) / Firebase Phone Auth (shopkeeper)
- **Password Hashing**: bcrypt with work factor 12
- **Session Management**: Device tracking, max devices per user
- **API Security**: Rate limiting, CORS, security headers
- **Data Protection**: TLS 1.3, encrypted storage, private S3

## Deployment Architecture (Stage A — Cost-Conscious)

```
Internet
    │
    ▼
Route53 (optional)
    │
    ▼
EC2 t3.micro (Ubuntu 24.04)
├── Caddy (reverse proxy + auto-TLS)
├── Docker Compose
│   ├── API (FastAPI + Uvicorn)
│   ├── Worker (Celery)
│   ├── Beat (Celery scheduler)
│   └── Redis (local container)
├── RDS PostgreSQL 16 + PostGIS (private)
└── S3 (object storage)
```

## Key Design Decisions

1. **Modular Monolith**: Single deployable unit with clear module boundaries
2. **PostgreSQL as Source of Truth**: All data persists in PostgreSQL; Redis is cache-only
3. **PostGIS for Geospatial**: All location queries use PostGIS functions (ST_DWithin, ST_Distance)
4. **Provider Abstraction**: Storage, SMS, email, push notifications use swappable providers
5. **Free-Tier First**: Architecture designed to minimize AWS costs

## Migration Path (Stage B — Scale)

- EC2 → ECS Fargate
- Local Redis → ElastiCache
- Caddy → ALB + CloudFront
- Add WAF for API protection
- Add OpenSearch if PostgreSQL search insufficient
