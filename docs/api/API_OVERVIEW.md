# Hyperlocal Product Discovery Platform — API Contract

## Base URL

| Environment | URL |
|-------------|-----|
| Development | `http://localhost:8000` |
| Staging | `https://staging-api.hyperlocal.in` |
| Production | `https://api.hyperlocal.in` |

## API Version

All endpoints are prefixed with `/api/v1`

## Response Envelope

All API responses follow a consistent envelope:

```json
{
  "success": true,
  "message": "Operation successful",
  "data": { ... }
}
```

Error responses:

```json
{
  "success": false,
  "message": "Error description",
  "error_code": "ERROR_CODE",
  "data": null
}
```

## Authentication

### Customer Authentication (OTP-based)

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/v1/auth/send-otp` | Send OTP to phone number |
| POST | `/api/v1/auth/verify-otp` | Verify OTP and get tokens |
| POST | `/api/v1/auth/register` | Register new customer |
| POST | `/api/v1/auth/refresh` | Refresh access token |
| POST | `/api/v1/auth/logout` | Logout and revoke session |
| GET | `/api/v1/auth/sessions` | List active sessions |
| DELETE | `/api/v1/auth/sessions/{id}` | Revoke specific session |
| GET | `/api/v1/auth/account-status` | Get account status |

### Shopkeeper Authentication (Firebase OTP)

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/v1/shopkeeper/auth/send-otp` | Send OTP via Firebase |
| POST | `/api/v1/shopkeeper/auth/verify-otp` | Verify OTP and get tokens |
| POST | `/api/v1/shopkeeper/auth/register` | Register new shopkeeper |
| POST | `/api/v1/shopkeeper/auth/login` | Login with credentials |
| POST | `/api/v1/shopkeeper/auth/refresh` | Refresh access token |
| POST | `/api/v1/shopkeeper/auth/logout` | Logout |
| GET | `/api/v1/shopkeeper/auth/me` | Get current user profile |

## Product Discovery

### Search Products

```
GET /api/v1/search/v2/products
```

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| q | string | No | Search query |
| latitude | float | No | User latitude (-90 to 90) |
| longitude | float | No | User longitude (-180 to 180) |
| radius_km | float | No | Search radius (default: 10, max: 100) |
| category | int | No | Category ID filter |
| brand | int | No | Brand ID filter |
| min_price | float | No | Minimum price |
| max_price | float | No | Maximum price |
| min_rating | float | No | Minimum rating (0-5) |
| in_stock | bool | No | Only in-stock items |
| sort | string | No | Sort order (relevance, distance, price_asc, etc.) |
| page | int | No | Page number (default: 1) |
| limit | int | No | Results per page (default: 20, max: 50) |

**Response:**

```json
{
  "success": true,
  "data": {
    "results": [
      {
        "id": 1,
        "name": "Product Name",
        "brand": "Brand Name",
        "category": "Category",
        "shop_products": [
          {
            "shop_id": 1,
            "shop_name": "Shop Name",
            "price": 250.00,
            "currency": "INR",
            "availability": "IN_STOCK",
            "distance_km": 1.2,
            "rating": 4.5
          }
        ]
      }
    ],
    "total": 100,
    "page": 1,
    "limit": 20
  }
}
```

### Barcode Lookup

```
GET /api/v1/search/v2/barcode/{barcode}
```

**Response:**

```json
{
  "success": true,
  "data": {
    "product": { ... },
    "shops": [
      {
        "shop_id": 1,
        "shop_name": "Shop Name",
        "price": 250.00,
        "availability": "IN_STOCK",
        "distance_km": 1.2
      }
    ]
  }
}
```

## Shops

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/v1/shops/nearby` | Find nearby shops |
| GET | `/api/v1/shops/{id}` | Get shop details |
| GET | `/api/v1/shops/{id}/products` | Get shop products |

### Nearby Shops

```
GET /api/v1/shops/nearby?latitude=12.97&longitude=77.59&radius_km=5
```

## Products

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/v1/products/{id}` | Get product details |
| GET | `/api/v1/products/{id}/shops` | Get shops with product |
| GET | `/api/v1/categories` | List categories |
| GET | `/api/v1/brands` | List brands |

## Shopkeeper Portal

### Shop Management

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/v1/shopkeeper/shops` | Create new shop |
| GET | `/api/v1/shopkeeper/shops` | List my shops |
| GET | `/api/v1/shopkeeper/shops/{id}` | Get shop details |
| PUT | `/api/v1/shopkeeper/shops/{id}` | Update shop |
| PUT | `/api/v1/shopkeeper/shops/{id}/location` | Update shop location |

### Inventory Management

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/v1/shopkeeper/shops/{id}/inventory` | Get inventory |
| POST | `/api/v1/shopkeeper/shops/{id}/products` | Add product |
| PUT | `/api/v1/shopkeeper/shops/{id}/products/{pid}` | Update product |
| DELETE | `/api/v1/shopkeeper/shops/{id}/products/{pid}` | Remove product |

## Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| UNAUTHORIZED | 401 | Authentication required |
| FORBIDDEN | 403 | Insufficient permissions |
| NOT_FOUND | 404 | Resource not found |
| VALIDATION_ERROR | 422 | Invalid input data |
| RATE_LIMITED | 429 | Too many requests |
| INTERNAL_ERROR | 500 | Server error |

## Rate Limits

| Endpoint | Limit |
|----------|-------|
| Default | 100 requests/minute |
| Auth endpoints | 5 requests/minute |
| Search | 30 requests/minute |

## Location Data Format

All location data uses WGS 84 (EPSG:4326) coordinate system:

```json
{
  "latitude": 12.9716,
  "longitude": 77.5946,
  "accuracy": 10.5,
  "source": "GPS"
}
```
