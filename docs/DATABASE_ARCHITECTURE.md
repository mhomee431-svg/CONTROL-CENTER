# Hyperlocal Product Discovery Platform — Database Architecture

## Overview

The database uses PostgreSQL 16 with PostGIS 3.4 extension for geospatial queries. The schema is designed for fast product discovery with proper normalization and indexing.

## Core Principles

1. **PostgreSQL is Source of Truth**: All data persists in PostgreSQL
2. **Redis is Cache-Only**: Redis never stores permanent data
3. **PostGIS for Geospatial**: All location queries use PostGIS functions
4. **Proper Normalization**: Product Master ≠ Shop Product ≠ Inventory ≠ Price

## Entity Relationship (Simplified)

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   users     │────<│   shops     │>────│  categories │
└─────────────┘     └─────────────┘     └─────────────┘
       │                   │
       │                   │
       v                   v
┌─────────────┐     ┌─────────────┐
│  customers  │     │ shop_products│>────┐
└─────────────┘     └─────────────┘     │
                                        │
┌─────────────┐     ┌─────────────┐     │
│   brands    │>────│product_masters│<───┘
└─────────────┘     └─────────────┘
                           │
                           v
                    ┌─────────────┐
                    │  inventory  │
                    └─────────────┘
```

## Key Tables

### Users & Authentication
- **users**: Core user accounts (phone, email, password)
- **roles**: RBAC roles (customer, shopkeeper, admin)
- **user_roles**: Many-to-many user-role mapping
- **auth_sessions**: Active sessions with device tracking
- **token_blacklist**: Revoked JWT tokens

### Products
- **product_masters**: Canonical product catalog
- **categories**: Hierarchical product categories
- **brands**: Product brands
- **product_variants**: Product variants (size, color, etc.)
- **product_identifiers**: Barcodes, SKUs, model numbers

### Shops
- **shops**: Business/shop locations (PostGIS Geography)
- **shop_owners**: Shop ownership mapping
- **shop_managers**: Shop manager mapping
- **shop_addresses**: Multiple addresses per shop
- **shop_hours**: Operating hours
- **shop_documents**: Verification documents

### Inventory & Pricing
- **shop_products**: Product availability in shops
- **inventory**: Stock levels and availability
- **price_history**: Historical pricing data
- **offers**: Promotional offers

### Discovery
- **search_indexes**: Denormalized search projection
- **search_history**: User search history
- **popular_searches**: Trending searches
- **barcode_scans**: Barcode scan events

### Analytics
- **analytics_events**: Unified event stream
- **product_views**: Product view tracking
- **shop_views**: Shop view tracking
- **audit_logs**: Tamper-evident audit trail

## PostGIS Usage

### Geography Columns
```sql
-- Shop location (primary geospatial column)
location GEOGRAPHY(POINT, 4326)

-- Spatial index
CREATE INDEX idx_shops_location ON shops USING GIST(location);
```

### Common Queries

#### Nearby Shops
```sql
SELECT s.*, ST_Distance(s.location, ST_MakePoint(:lon, :lat)::geography) as distance
FROM shops s
WHERE ST_DWithin(s.location, ST_MakePoint(:lon, :lat)::geography, :radius_meters)
ORDER BY distance;
```

#### Shop Count in Radius
```sql
SELECT COUNT(*) FROM shops
WHERE ST_DWithin(location, ST_MakePoint(:lon, :lat)::geography, :radius_meters);
```

## Indexing Strategy

### Primary Indexes
- Primary keys (auto-indexed)
- Foreign keys (explicit indexes)
- Unique constraints (unique indexes)

### Performance Indexes
- **shops.location**: GiST index for geospatial queries
- **product_masters.name**: B-tree index for text search
- **shop_products(shop_id, product_master_id)**: Composite index
- **search_indexes.search_text**: GIN index for full-text search

### Partial Indexes
- **product_masters WHERE prescription_required**: For pharmacy filtering
- **shops WHERE status = 'ACTIVE'**: For active shop queries

## Migrations

All schema changes are managed via Alembic migrations:

| Migration | Description |
|-----------|-------------|
| 0001 | Initial schema (users, roles) |
| 0002 | Expanded architecture |
| 0003 | Product master catalog |
| 0004 | Shop management system |
| 0005 | Inventory & pricing engine |
| 0006 | Search & geo discovery |
| 0007 | Inventory import jobs |
| 0008 | POS integration |
| 0009 | Notification system |
| 0010 | Subscription monetization |
| 0011 | Analytics & audit |
| 0012 | Fast2SMS OTP records |
| 0013 | Google OAuth leads |
| 0014 | Module schema completion |
| 0015 | Restaurant discovery |
| 0016 | Transport booking |
| 0017 | Reviews & pharma compliance |
| 0018 | Shop location metadata |

## Backup Strategy

- **Automated Backups**: 7-day retention
- **Point-in-Time Recovery**: Available within retention window
- **Final Snapshot**: Taken on destroy
- **Restore Testing**: Monthly restore drills

## Performance Targets

| Query Type | Target |
|------------|--------|
| Simple lookup | < 50ms |
| Product search | < 200ms |
| Nearby shops | < 300ms |
| Complex filter | < 500ms |
