# Hyperlocal Customer App — Definitive API Contract

**Version:** 1.0.0  
**Status:** APPROVED  
**Last Updated:** 2026-08-19  
**Owner:** Backend Platform Team

---

## 1. Overview

This document defines the **complete, definitive API contract** between:

| Consumer | Base Path |
|---|---|
| Customer App (Flutter) | `/api/v1` |
| Shopkeeper App | `/api/v1/shopkeeper` |
| Admin Panel | `/api/v1/admin` |
| Backend Services | `/api/v1` |
| Search Services | `/api/v1/search` |
| Inventory Services | `/api/v1/inventory` |
| Notification Services | `/api/v1/notifications` |
| Payment Services | `/api/v1/payments` |

All endpoints are **RESTful**, use **JSON** for request/response bodies, and are served over **HTTPS** only.

---

## 2. API Versioning Strategy

### 2.1 Versioning Scheme
- **URL Path Versioning:** `/api/v1/...`
- Current version: **v1**
- Future versions: `v2`, `v3`, etc.

### 2.2 Version Lifecycle
| Stage | Duration | Behavior |
|---|---|---|
| **Preview** | 30 days | Available at `/api/v1-preview/...` |
| **Active** | 12+ months | Available at `/api/v1/...` |
| **Deprecated** | 6 months | Still served, returns `Deprecation` header |
| **Sunset** | — | Returns `410 Gone` |

### 2.3 Version Headers
- `X-API-Version: 1` — Requested version (optional, defaults to latest)
- `X-API-Deprecated: true` — Response header when version is deprecated
- `X-API-Sunset-Date: 2027-01-01` — Response header indicating removal date

### 2.4 Backwards Compatibility Rules
1. **Additive changes only** within a major version.
2. New optional fields may be added to responses.
3. New endpoints may be added.
4. **Breaking changes** (removing fields, changing types, changing paths) require a new major version.
5. All deprecated endpoints must return a `Deprecation` header for at least 6 months.
6. Clients must ignore unknown fields in responses (forward compatibility).
7. Clients must send `Accept: application/json` header.

---

## 3. Standard Response Structures

### 3.1 Success Response
```json
{
  "success": true,
  "message": "Operation completed successfully",
  "data": { }
}
```

| Field | Type | Description |
|---|---|---|
| `success` | boolean | Always `true` for 2xx responses |
| `message` | string | Human-readable success message |
| `data` | object/array/null | Payload. `null` for operations with no return data |

### 3.2 Error Response
```json
{
  "success": false,
  "message": "Human-readable error message",
  "error_code": "PRODUCT_NOT_FOUND",
  "data": {
    "field_errors": {
      "price": "Must be greater than 0"
    },
    "request_id": "req_abc123"
  }
}
```

| Field | Type | Description |
|---|---|---|
| `success` | boolean | Always `false` for error responses |
| `message` | string | Human-readable error message |
| `error_code` | string | Machine-readable error code (see §4) |
| `data` | object/null | Optional error details |
| `data.field_errors` | object | Field-level validation errors |
| `data.request_id` | string | Correlation ID for support/debugging |

### 3.3 Standard Pagination Structure
All list endpoints return paginated responses using this structure:

```json
{
  "success": true,
  "message": "Success",
  "data": {
    "items": [ ],
    "pagination": {
      "page": 1,
      "limit": 20,
      "total": 150,
      "total_pages": 8,
      "has_more": true,
      "next_cursor": "eyJpZCI6MTAwfQ==",
      "prev_cursor": null
    }
  }
}
```

| Field | Type | Description |
|---|---|---|
| `items` | array | Array of result objects |
| `pagination.page` | int | Current page (1-based) |
| `pagination.limit` | int | Items per page (default 20, max 100) |
| `pagination.total` | int | Total number of items |
| `pagination.total_pages` | int | Total number of pages |
| `pagination.has_more` | boolean | Whether more pages exist |
| `pagination.next_cursor` | string/null | Cursor for next page (cursor-based) |
| `pagination.prev_cursor` | string/null | Cursor for previous page |

**Pagination Query Parameters:**
- `page` (int, default 1, min 1) — Page number (offset-based)
- `limit` (int, default 20, min 1, max 100) — Items per page
- `cursor` (string) — Cursor for cursor-based pagination (overrides `page`)

### 3.4 Standard Filtering
Filtering is done via query parameters:
- `filter[field]=value` — Exact match
- `filter[field]=value1,value2` — IN list
- `filter[field_min]=X&filter[field_max]=Y` — Range
- `filter[field_like]=text` — Partial match (LIKE)

### 3.5 Standard Sorting
- `sort=field` — Ascending
- `sort=-field` — Descending
- `sort=field1,-field2` — Multiple fields
- Allowed sort fields are documented per endpoint.

---

## 4. Standard Error Codes

| HTTP Status | Error Code | Description |
|---|---|---|
| 400 | `VALIDATION_ERROR` | Request validation failed |
| 400 | `INVALID_OTP` | OTP is invalid or expired |
| 400 | `INVALID_QUERY` | Query parameters are invalid |
| 401 | `UNAUTHORIZED` | Missing or invalid authentication token |
| 401 | `TOKEN_EXPIRED` | Access token has expired |
| 401 | `INVALID_REFRESH_TOKEN` | Refresh token is invalid or expired |
| 403 | `FORBIDDEN` | Authenticated but not authorized |
| 403 | `INSUFFICIENT_PERMISSIONS` | User lacks required role/permission |
| 404 | `NOT_FOUND` | Generic not found |
| 404 | `USER_NOT_FOUND` | User does not exist |
| 404 | `PRODUCT_NOT_FOUND` | Product does not exist |
| 404 | `SHOP_NOT_FOUND` | Shop does not exist |
| 404 | `CATEGORY_NOT_FOUND` | Category does not exist |
| 404 | `BRAND_NOT_FOUND` | Brand does not exist |
| 404 | `NOTIFICATION_NOT_FOUND` | Notification does not exist |
| 404 | `NOT_SAVED` | Item is not in saved list |
| 404 | `OFFER_NOT_FOUND` | Offer does not exist |
| 404 | `COMPLAINT_NOT_FOUND` | Complaint does not exist |
| 404 | `REPORT_NOT_FOUND` | Report does not exist |
| 404 | `SUBSCRIPTION_NOT_FOUND` | Subscription does not exist |
| 404 | `PAYMENT_NOT_FOUND` | Payment does not exist |
| 404 | `POS_INTEGRATION_NOT_FOUND` | POS integration does not exist |
| 409 | `CONFLICT` | Resource already exists |
| 409 | `PHONE_ALREADY_REGISTERED` | Phone number already registered |
| 409 | `ALREADY_SAVED` | Item already in saved list |
| 409 | `SHOP_ALREADY_REGISTERED` | Shop already registered for this user |
| 422 | `UNPROCESSABLE_ENTITY` | Request body is semantically invalid |
| 429 | `RATE_LIMIT_EXCEEDED` | Rate limit exceeded |
| 500 | `INTERNAL_ERROR` | Unexpected server error |
| 503 | `SERVICE_UNAVAILABLE` | Service temporarily unavailable |

---

## 5. Authentication & Authorization

### 5.1 Authentication Method
- **Bearer Token (JWT)** in `Authorization: Bearer <access_token>` header.
- Access token TTL: **15 minutes**
- Refresh token TTL: **30 days**
- Refresh tokens are rotated on every refresh.

### 5.2 Roles
| Role | Description |
|---|---|
| `CUSTOMER` | End-user of the Customer App |
| `SHOPKEEPER` | Shop owner/manager using the Shopkeeper App |
| `ADMIN` | Platform administrator using the Admin Panel |
| `SUPER_ADMIN` | Super administrator with all permissions |

### 5.3 Authorization Model
- **Ownership rules:** Users can only access their own resources (saved items, notifications, search history, profile).
- **Shop ownership:** Shopkeepers can only manage shops they own or manage.
- **Admin scope:** Admins can access all resources within their permission scope.
- **Permission checks** are enforced server-side on every protected endpoint.

### 5.4 Rate Limits
| Endpoint Group | Rate Limit |
|---|---|
| Auth (send-otp) | 5 requests / 15 min per phone |
| Auth (verify-otp) | 10 requests / 15 min per phone |
| General API | 100 requests / min per user |
| Search | 60 requests / min per user |
| Admin API | 300 requests / min per admin |
| Shopkeeper API | 200 requests / min per shopkeeper |

Rate limit headers on all responses:
- `X-RateLimit-Limit`
- `X-RateLimit-Remaining`
- `X-RateLimit-Reset`

---

## 6. Authentication APIs

### 6.1 Send OTP
- **Method:** `POST`
- **Path:** `/api/v1/auth/send-otp`
- **Auth:** None
- **Rate Limit:** 5 / 15 min per phone

**Request Body:**
```json
{
  "phone_number": "+919876543210"
}
```

| Field | Type | Required | Validation |
|---|---|---|---|
| `phone_number` | string | Yes | 10–15 chars, E.164 format |

**Response (200):**
```json
{
  "success": true,
  "message": "OTP sent successfully",
  "data": {
    "message": "OTP sent successfully",
    "dev_otp": "123456"
  }
}
```

**Error Cases:**
| Status | Code | Condition |
|---|---|---|
| 400 | `VALIDATION_ERROR` | Invalid phone number |
| 429 | `RATE_LIMIT_EXCEEDED` | Too many OTP requests |

**Idempotency:** No (each call generates a new OTP).

### 6.2 Verify OTP & Login
- **Method:** `POST`
- **Path:** `/api/v1/auth/verify-otp`
- **Auth:** None
- **Rate Limit:** 10 / 15 min per phone

**Request Body:**
```json
{
  "phone_number": "+919876543210",
  "otp": "123456"
}
```

| Field | Type | Required | Validation |
|---|---|---|---|
| `phone_number` | string | Yes | 10–15 chars |
| `otp` | string | Yes | 4–8 chars, numeric |

**Response (200):**
```json
{
  "success": true,
  "message": "Login successful",
  "data": {
    "access_token": "eyJhbGciOi...",
    "refresh_token": "eyJhbGciOi...",
    "token_type": "bearer"
  }
}
```

**Error Cases:**
| Status | Code | Condition |
|---|---|---|
| 400 | `INVALID_OTP` | OTP is invalid or expired |
| 429 | `RATE_LIMIT_EXCEEDED` | Too many attempts |

**Idempotency:** No.

### 6.3 Refresh Token
- **Method:** `POST`
- **Path:** `/api/v1/auth/refresh`
- **Auth:** None (uses refresh token)

**Request Body:**
```json
{
  "refresh_token": "eyJhbGciOi..."
}
```

**Response (200):**
```json
{
  "success": true,
  "message": "Token refreshed",
  "data": {
    "access_token": "eyJhbGciOi...",
    "refresh_token": "eyJhbGciOi...",
    "token_type": "bearer"
  }
}
```

**Error Cases:**
| Status | Code | Condition |
|---|---|---|
| 401 | `INVALID_REFRESH_TOKEN` | Refresh token invalid/expired |
| 404 | `USER_NOT_FOUND` | User no longer exists |

**Idempotency:** No (rotates tokens).

### 6.4 Logout
- **Method:** `POST`
- **Path:** `/api/v1/auth/logout`
- **Auth:** Bearer token required
- **Authorization:** Any authenticated user

**Request Body:** None

**Response (200):**
```json
{
  "success": true,
  "message": "Logged out successfully",
  "data": null
}
```

**Idempotency:** Yes.

---

## 7. Customer APIs

### 7.1 Get Current User
- **Method:** `GET`
- **Path:** `/api/v1/users/me`
- **Auth:** Bearer token required
- **Authorization:** Any authenticated user (self only)

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "id": 1,
    "name": "John Doe",
    "email": "john@example.com",
    "phone_number": "+919876543210",
    "avatar_url": "https://cdn.example.com/avatars/1.jpg",
    "is_active": true,
    "created_at": "2026-01-01T00:00:00Z",
    "updated_at": "2026-01-01T00:00:00Z"
  }
}
```

**Error Cases:**
| Status | Code | Condition |
|---|---|---|
| 401 | `UNAUTHORIZED` | Missing/invalid token |

### 7.2 Update Current User
- **Method:** `PUT`
- **Path:** `/api/v1/users/me`
- **Auth:** Bearer token required
- **Authorization:** Any authenticated user (self only)

**Request Body:**
```json
{
  "name": "John Doe",
  "email": "john@example.com",
  "avatar_url": "https://cdn.example.com/avatars/1.jpg"
}
```

| Field | Type | Required | Validation |
|---|---|---|---|
| `name` | string | No | Max 120 chars |
| `email` | string | No | Valid email format |
| `avatar_url` | string | No | Valid URL, max 500 chars |

**Response (200):** Same as `GET /users/me`.

**Error Cases:**
| Status | Code | Condition |
|---|---|---|
| 400 | `VALIDATION_ERROR` | Invalid field values |
| 401 | `UNAUTHORIZED` | Missing/invalid token |

**Idempotency:** Yes (PUT semantics).

### 7.3 Delete Current User
- **Method:** `DELETE`
- **Path:** `/api/v1/users/me`
- **Auth:** Bearer token required
- **Authorization:** Any authenticated user (self only)

**Response (200):**
```json
{
  "success": true,
  "message": "Account deleted",
  "data": null
}
```

**Idempotency:** Yes (subsequent calls return 404).

### 7.4 Get Profile
- **Method:** `GET`
- **Path:** `/api/v1/profile`
- **Auth:** Bearer token required
- **Authorization:** Any authenticated user (self only)

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "id": 1,
    "name": "John Doe",
    "email": "john@example.com",
    "phone_number": "+919876543210",
    "avatar_url": "https://cdn.example.com/avatars/1.jpg",
    "created_at": "2026-01-01T00:00:00Z"
  }
}
```

### 7.5 Update Profile
- **Method:** `PUT`
- **Path:** `/api/v1/profile`
- **Auth:** Bearer token required
- **Authorization:** Any authenticated user (self only)

**Request Body:**
```json
{
  "name": "John Doe",
  "email": "john@example.com",
  "avatar_url": "https://cdn.example.com/avatars/1.jpg"
}
```

**Response (200):** Same as `GET /profile`.

**Idempotency:** Yes.

---

## 8. Location APIs

### 8.1 Get Nearby Shops (Location-based)
- **Method:** `GET`
- **Path:** `/api/v1/locations/nearby`
- **Auth:** None (public)
- **Rate Limit:** 60 / min

**Query Parameters:**
| Param | Type | Required | Validation |
|---|---|---|---|
| `latitude` | float | Yes | -90 to 90 |
| `longitude` | float | Yes | -180 to 180 |
| `radius_km` | float | No | 0.1 to 100, default 5.0 |

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "user_lat": 25.5941,
    "user_lng": 85.1376,
    "radius_km": 5.0,
    "shops": [
      {
        "shop_id": 1,
        "shop_name": "Patna Medical Store",
        "distance_km": 0.5,
        "latitude": 25.5941,
        "longitude": 85.1376,
        "address": "Main Road, Patna"
      }
    ]
  }
}
```

**Error Cases:**
| Status | Code | Condition |
|---|---|---|
| 400 | `VALIDATION_ERROR` | Invalid coordinates |

### 8.2 Manual Location Search
- **Method:** `GET`
- **Path:** `/api/v1/locations/manual-search`
- **Auth:** None (public)

**Query Parameters:**
| Param | Type | Required | Validation |
|---|---|---|---|
| `q` | string | Yes | 1–100 chars |

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": [
    {
      "city": "Patna",
      "state": "Bihar",
      "pincode": "800001",
      "latitude": 25.5941,
      "longitude": 85.1376,
      "is_manual": true
    }
  ]
}
```

---

## 9. Category APIs

### 9.1 List Categories
- **Method:** `GET`
- **Path:** `/api/v1/categories`
- **Auth:** None (public)

**Query Parameters:**
| Param | Type | Required | Validation |
|---|---|---|---|
| `page` | int | No | Default 1 |
| `limit` | int | No | Default 20, max 100 |
| `sort` | string | No | `name`, `-name`, `sort_order`, `-sort_order` |

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "items": [
      {
        "id": 1,
        "name": "Medicines",
        "icon_url": "https://cdn.example.com/icons/medicines.png",
        "created_at": "2026-01-01T00:00:00Z"
      }
    ],
    "pagination": {
      "page": 1,
      "limit": 20,
      "total": 10,
      "total_pages": 1,
      "has_more": false,
      "next_cursor": null,
      "prev_cursor": null
    }
  }
}
```

### 9.2 Get Category by ID
- **Method:** `GET`
- **Path:** `/api/v1/categories/{category_id}`
- **Auth:** None (public)

**Path Parameters:**
| Param | Type | Required | Validation |
|---|---|---|---|
| `category_id` | int | Yes | Positive integer |

**Response (200):** Single category object.

**Error Cases:**
| Status | Code | Condition |
|---|---|---|
| 404 | `CATEGORY_NOT_FOUND` | Category does not exist |

---

## 10. Brand APIs

### 10.1 List Brands
- **Method:** `GET`
- **Path:** `/api/v1/brands`
- **Auth:** None (public)

**Query Parameters:**
| Param | Type | Required | Validation |
|---|---|---|---|
| `page` | int | No | Default 1 |
| `limit` | int | No | Default 20, max 100 |
| `sort` | string | No | `name`, `-name` |
| `filter[is_active]` | boolean | No | Filter by active status |

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "items": [
      {
        "id": 1,
        "name": "Dabur",
        "slug": "dabur",
        "logo_url": "https://cdn.example.com/logos/dabur.png",
        "is_active": true
      }
    ],
    "pagination": { }
  }
}
```

### 10.2 Get Brand by ID
- **Method:** `GET`
- **Path:** `/api/v1/brands/{brand_id}`
- **Auth:** None (public)

**Error Cases:**
| Status | Code | Condition |
|---|---|---|
| 404 | `BRAND_NOT_FOUND` | Brand does not exist |

---

## 11. Product APIs

### 11.1 Get Product by Barcode
- **Method:** `GET`
- **Path:** `/api/v1/products/{barcode}`
- **Auth:** None (public)
- **Rate Limit:** 30 / min

**Path Parameters:**
| Param | Type | Required | Validation |
|---|---|---|---|
| `barcode` | string | Yes | EAN-13, UPC-A, or QR code value |

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "id": 1,
    "name": "Paracetamol 500mg",
    "brand": "Dabur",
    "category": "Medicines",
    "barcode": "8901234567890",
    "image_url": "https://cdn.example.com/products/1.jpg",
    "description": "Pain relief tablets"
  }
}
```

**Error Cases:**
| Status | Code | Condition |
|---|---|---|
| 404 | `PRODUCT_NOT_FOUND` | No product with this barcode |

### 11.2 Get Product by ID
- **Method:** `GET`
- **Path:** `/api/v1/products/id/{product_id}`
- **Auth:** None (public)

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "id": 1,
    "name": "Paracetamol 500mg",
    "slug": "paracetamol-500mg",
    "description": "Pain relief tablets",
    "short_description": "500mg paracetamol",
    "category": {
      "id": 1,
      "name": "Medicines"
    },
    "brand": {
      "id": 1,
      "name": "Dabur"
    },
    "base_unit": "strip",
    "base_quantity": 10,
    "images": [
      {
        "id": 1,
        "image_url": "https://cdn.example.com/products/1.jpg",
        "thumbnail_url": "https://cdn.example.com/products/1_thumb.jpg",
        "is_primary": true
      }
    ],
    "variants": [
      {
        "id": 1,
        "sku": "PARA-500-10",
        "name": "Paracetamol 500mg (10 tablets)",
        "attributes": { "pack_size": "10" }
      }
    ],
    "attributes": [
      {
        "name": "Pack Size",
        "values": ["10", "20"]
      }
    ],
    "is_active": true,
    "is_featured": false
  }
}
```

**Error Cases:**
| Status | Code | Condition |
|---|---|---|
| 404 | `PRODUCT_NOT_FOUND` | Product does not exist |

### 11.3 Compare Product Prices
- **Method:** `GET`
- **Path:** `/api/v1/products/{product_id}/compare`
- **Auth:** None (public)

**Query Parameters:**
| Param | Type | Required | Validation |
|---|---|---|---|
| `latitude` | float | No | -90 to 90 |
| `longitude` | float | No | -180 to 180 |
| `radius_km` | float | No | 0.1 to 100, default 10.0 |
| `sort` | string | No | `nearest`, `lowest_price`, `highest_rated` |

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "product_details": {
      "id": 1,
      "name": "Paracetamol 500mg",
      "brand": "Dabur",
      "category": "Medicines",
      "barcode": "8901234567890",
      "image_url": "https://cdn.example.com/products/1.jpg",
      "description": "Pain relief tablets"
    },
    "shop_inventories": [
      {
        "shop_id": 1,
        "shop_name": "Patna Medical Store",
        "price": 25.50,
        "availability_status": "In Stock",
        "distance_km": 0.5
      }
    ]
  }
}
```

**Error Cases:**
| Status | Code | Condition |
|---|---|---|
| 404 | `PRODUCT_NOT_FOUND` | Product does not exist |

---

## 12. Product Variant APIs

### 12.1 List Product Variants
- **Method:** `GET`
- **Path:** `/api/v1/products/{product_id}/variants`
- **Auth:** None (public)

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "items": [
      {
        "id": 1,
        "product_master_id": 1,
        "sku": "PARA-500-10",
        "name": "Paracetamol 500mg (10 tablets)",
        "description": "Strip of 10 tablets",
        "attributes": { "pack_size": "10" },
        "is_active": true,
        "images": [
          {
            "id": 1,
            "image_url": "https://cdn.example.com/products/1.jpg",
            "is_primary": true
          }
        ]
      }
    ],
    "pagination": { }
  }
}
```

### 12.2 Get Variant by ID
- **Method:** `GET`
- **Path:** `/api/v1/variants/{variant_id}`
- **Auth:** None (public)

**Error Cases:**
| Status | Code | Condition |
|---|---|---|
| 404 | `PRODUCT_NOT_FOUND` | Variant does not exist |

---

## 13. Shop APIs

### 13.1 Get Nearby Shops
- **Method:** `GET`
- **Path:** `/api/v1/shops/nearby`
- **Auth:** None (public)

**Query Parameters:**
| Param | Type | Required | Validation |
|---|---|---|---|
| `latitude` | float | Yes | -90 to 90 |
| `longitude` | float | Yes | -180 to 180 |
| `radius_km` | float | No | 0.1 to 100, default 5.0 |
| `page` | int | No | Default 1 |
| `limit` | int | No | Default 20, max 100 |
| `sort` | string | No | `nearest`, `rating`, `-rating` |

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "items": [
      {
        "id": 1,
        "name": "Patna Medical Store",
        "image_url": "https://cdn.example.com/shops/1.jpg",
        "distance_km": 0.5,
        "rating": 4.5,
        "is_verified": true
      }
    ],
    "pagination": { }
  }
}
```

### 13.2 Get Shop by ID
- **Method:** `GET`
- **Path:** `/api/v1/shops/{shop_id}`
- **Auth:** None (public)

**Query Parameters:**
| Param | Type | Required | Validation |
|---|---|---|---|
| `latitude` | float | No | -90 to 90 |
| `longitude` | float | No | -180 to 180 |

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "id": 1,
    "name": "Patna Medical Store",
    "description": "Local medical store",
    "image_url": "https://cdn.example.com/shops/1.jpg",
    "phone": "+919876543210",
    "address": "Main Road, Patna",
    "latitude": 25.5941,
    "longitude": 85.1376,
    "rating": 4.5,
    "review_count": 120,
    "is_verified": true,
    "opening_hours": "9:00 AM - 9:00 PM",
    "created_at": "2026-01-01T00:00:00Z",
    "updated_at": "2026-01-01T00:00:00Z",
    "distance_km": 0.5,
    "is_open_now": true,
    "last_inventory_update": "2026-08-19T10:00:00Z",
    "active_offers": ["10% off on all medicines"],
    "available_products": [
      {
        "product_id": 1,
        "name": "Paracetamol 500mg",
        "image_url": "https://cdn.example.com/products/1.jpg",
        "price": 25.50,
        "is_available": true,
        "stock_status": "IN_STOCK"
      }
    ],
    "is_saved": false
  }
}
```

**Error Cases:**
| Status | Code | Condition |
|---|---|---|
| 404 | `SHOP_NOT_FOUND` | Shop does not exist |

### 13.3 Get Shop Products
- **Method:** `GET`
- **Path:** `/api/v1/shops/{shop_id}/products`
- **Auth:** None (public)

**Query Parameters:**
| Param | Type | Required | Validation |
|---|---|---|---|
| `page` | int | No | Default 1 |
| `limit` | int | No | Default 20, max 100 |
| `sort` | string | No | `name`, `price`, `-price`, `stock_status` |
| `filter[category_id]` | int | No | Filter by category |
| `filter[in_stock]` | boolean | No | Only in-stock items |

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "items": [
      {
        "product_id": 1,
        "name": "Paracetamol 500mg",
        "brand": "Dabur",
        "image_url": "https://cdn.example.com/products/1.jpg",
        "price": 25.50,
        "is_available": true,
        "stock_status": "IN_STOCK"
      }
    ],
    "pagination": { }
  }
}
```

**Error Cases:**
| Status | Code | Condition |
|---|---|---|
| 404 | `SHOP_NOT_FOUND` | Shop does not exist |

---

## 14. Shop Product APIs

### 14.1 Get Shop Product Detail
- **Method:** `GET`
- **Path:** `/api/v1/shops/{shop_id}/products/{product_id}`
- **Auth:** None (public)

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "shop_product_id": 1,
    "shop_id": 1,
    "product_id": 1,
    "variant_id": null,
    "product_name": "Paracetamol 500mg",
    "product_image_url": "https://cdn.example.com/products/1.jpg",
    "price": 25.50,
    "mrp": 30.00,
    "is_available": true,
    "stock_status": "IN_STOCK",
    "quantity": 100,
    "last_inventory_update": "2026-08-19T10:00:00Z",
    "last_price_update": "2026-08-19T10:00:00Z",
    "offers": [
      {
        "id": 1,
        "title": "10% off",
        "offer_type": "PERCENTAGE_DISCOUNT",
        "discount_percentage": 10.0
      }
    ]
  }
}
```

**Error Cases:**
| Status | Code | Condition |
|---|---|---|
| 404 | `SHOP_NOT_FOUND` | Shop does not exist |
| 404 | `PRODUCT_NOT_FOUND` | Product not sold at this shop |

---

## 15. Inventory APIs

### 15.1 Get Product Inventory (Across Shops)
- **Method:** `GET`
- **Path:** `/api/v1/inventory/product/{product_master_id}`
- **Auth:** None (public)

**Query Parameters:**
| Param | Type | Required | Validation |
|---|---|---|---|
| `latitude` | float | No | -90 to 90 |
| `longitude` | float | No | -180 to 180 |
| `radius_km` | float | No | 0.1 to 100, default 10.0 |
| `sort` | string | No | `nearest`, `lowest_price`, `highest_rated` |

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "product_id": 1,
    "items": [
      {
        "product_id": 1,
        "product_name": "Paracetamol 500mg",
        "product_image_url": "https://cdn.example.com/products/1.jpg",
        "shop_id": 1,
        "shop_name": "Patna Medical Store",
        "price": 25.50,
        "quantity": 100,
        "stock_status": "IN_STOCK",
        "distance_km": 0.5,
        "shop_rating": 4.5,
        "updated_at": "2026-08-19T10:00:00Z"
      }
    ]
  }
}
```

**Error Cases:**
| Status | Code | Condition |
|---|---|---|
| 404 | `PRODUCT_NOT_FOUND` | Product does not exist |

### 15.2 Get Shop Inventory
- **Method:** `GET`
- **Path:** `/api/v1/inventory/shop/{shop_id}`
- **Auth:** None (public)

**Query Parameters:**
| Param | Type | Required | Validation |
|---|---|---|---|
| `page` | int | No | Default 1 |
| `limit` | int | No | Default 20, max 100 |
| `filter[in_stock]` | boolean | No | Only in-stock items |
| `filter[category_id]` | int | No | Filter by category |

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "shop_id": 1,
    "items": [
      {
        "id": 1,
        "product_id": 1,
        "shop_id": 1,
        "price": 25.50,
        "quantity": 100,
        "is_available": true,
        "stock_status": "IN_STOCK",
        "updated_at": "2026-08-19T10:00:00Z"
      }
    ],
    "pagination": { }
  }
}
```

**Error Cases:**
| Status | Code | Condition |
|---|---|---|
| 404 | `SHOP_NOT_FOUND` | Shop does not exist |

---

## 16. Pricing APIs

### 16.1 Get Price History
- **Method:** `GET`
- **Path:** `/api/v1/products/{product_id}/price-history`
- **Auth:** None (public)

**Query Parameters:**
| Param | Type | Required | Validation |
|---|---|---|---|
| `shop_id` | int | No | Filter by shop |
| `from` | datetime | No | Start date |
| `to` | datetime | No | End date |
| `page` | int | No | Default 1 |
| `limit` | int | No | Default 20, max 100 |

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "items": [
      {
        "id": 1,
        "shop_product_id": 1,
        "shop_id": 1,
        "shop_name": "Patna Medical Store",
        "old_price": 30.00,
        "new_price": 25.50,
        "effective_from": "2026-08-01T00:00:00Z",
        "effective_to": null
      }
    ],
    "pagination": { }
  }
}
```

---

## 17. Offer APIs

### 17.1 List Active Offers
- **Method:** `GET`
- **Path:** `/api/v1/offers`
- **Auth:** None (public)

**Query Parameters:**
| Param | Type | Required | Validation |
|---|---|---|---|
| `shop_id` | int | No | Filter by shop |
| `product_id` | int | No | Filter by product |
| `page` | int | No | Default 1 |
| `limit` | int | No | Default 20, max 100 |

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "items": [
      {
        "id": 1,
        "shop_id": 1,
        "shop_name": "Patna Medical Store",
        "title": "10% off on all medicines",
        "description": "Get 10% off on all medicines",
        "offer_type": "PERCENTAGE_DISCOUNT",
        "discount_percentage": 10.0,
        "min_purchase_amount": 100.00,
        "max_discount_amount": 50.00,
        "start_date": "2026-08-01T00:00:00Z",
        "end_date": "2026-08-31T23:59:59Z",
        "terms_conditions": "Valid on all medicines"
      }
    ],
    "pagination": { }
  }
}
```

### 17.2 Get Offer by ID
- **Method:** `GET`
- **Path:** `/api/v1/offers/{offer_id}`
- **Auth:** None (public)

**Error Cases:**
| Status | Code | Condition |
|---|---|---|
| 404 | `OFFER_NOT_FOUND` | Offer does not exist |

---

## 18. Search APIs

### 18.1 Search Products
- **Method:** `GET`
- **Path:** `/api/v1/search/products`
- **Auth:** None (public)
- **Rate Limit:** 60 / min

**Query Parameters:**
| Param | Type | Required | Validation |
|---|---|---|---|
| `q` | string | No | Max 200 chars |
| `latitude` | float | No | -90 to 90 |
| `longitude` | float | No | -180 to 180 |
| `radius_km` | float | No | 0.1 to 100, default 10.0 |
| `category` | int | No | Category ID filter |
| `brand` | int | No | Brand ID filter |
| `min_price` | float | No | >= 0 |
| `max_price` | float | No | >= 0 |
| `in_stock` | boolean | No | Only in-stock items |
| `sort` | string | No | `nearest`, `lowest_price`, `highest_rated`, `recently_updated` |
| `page` | int | No | Default 1 |
| `limit` | int | No | Default 10, max 50 |

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "results": [
      {
        "id": "res_1",
        "product_id": 1,
        "product_name": "Paracetamol 500mg",
        "product_image_url": "https://cdn.example.com/products/1.jpg",
        "shop_id": 1,
        "shop_name": "Patna Medical Store",
        "price": 25.50,
        "is_available": true,
        "stock_status": "IN_STOCK",
        "distance_km": 0.5,
        "shop_rating": 4.5,
        "last_updated": "2026-08-19T10:00:00Z",
        "offer_text": "10% off"
      }
    ],
    "page": 1,
    "limit": 10,
    "has_more": false,
    "total": 1
  }
}
```

**Error Cases:**
| Status | Code | Condition |
|---|---|---|
| 400 | `VALIDATION_ERROR` | Invalid query parameters |
| 429 | `RATE_LIMIT_EXCEEDED` | Too many search requests |

### 18.2 Search Suggestions
- **Method:** `GET`
- **Path:** `/api/v1/search/suggestions`
- **Auth:** None (public)

**Query Parameters:**
| Param | Type | Required | Validation |
|---|---|---|---|
| `q` | string | Yes | 1–100 chars |

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": [
    {
      "text": "Paracetamol 500mg",
      "is_category": false,
      "is_brand": false
    },
    {
      "text": "Dabur",
      "is_category": false,
      "is_brand": true
    }
  ]
}
```

### 18.3 Get Search History
- **Method:** `GET`
- **Path:** `/api/v1/search/history`
- **Auth:** Bearer token required
- **Authorization:** Any authenticated user (self only)

**Query Parameters:**
| Param | Type | Required | Validation |
|---|---|---|---|
| `page` | int | No | Default 1 |
| `limit` | int | No | Default 20, max 100 |

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "items": [
      {
        "id": 1,
        "query": "Paracetamol",
        "result_count": 5,
        "is_successful": true,
        "searched_at": "2026-08-19T10:00:00Z"
      }
    ],
    "pagination": { }
  }
}
```

### 18.4 Clear Search History
- **Method:** `DELETE`
- **Path:** `/api/v1/search/history`
- **Auth:** Bearer token required
- **Authorization:** Any authenticated user (self only)

**Response (200):**
```json
{
  "success": true,
  "message": "Search history cleared",
  "data": null
}
```

**Idempotency:** Yes.

### 18.5 Delete Single Search History Entry
- **Method:** `DELETE`
- **Path:** `/api/v1/search/history/{history_id}`
- **Auth:** Bearer token required
- **Authorization:** Any authenticated user (self only)

**Error Cases:**
| Status | Code | Condition |
|---|---|---|
| 404 | `NOT_FOUND` | History entry not found |

**Idempotency:** Yes.

### 18.6 Get Popular Searches
- **Method:** `GET`
- **Path:** `/api/v1/search/popular`
- **Auth:** None (public)

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "items": [
      {
        "query": "Paracetamol",
        "search_count": 1000
      }
    ]
  }
}
```

---

## 19. Nearby Shop APIs

### 19.1 Get Nearby Shops with Products
- **Method:** `GET`
- **Path:** `/api/v1/shops/nearby/products`
- **Auth:** None (public)

**Query Parameters:**
| Param | Type | Required | Validation |
|---|---|---|---|
| `latitude` | float | Yes | -90 to 90 |
| `longitude` | float | Yes | -180 to 180 |
| `radius_km` | float | No | 0.1 to 100, default 5.0 |
| `product_id` | int | No | Filter shops selling this product |
| `page` | int | No | Default 1 |
| `limit` | int | No | Default 20, max 100 |

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "items": [
      {
        "shop_id": 1,
        "shop_name": "Patna Medical Store",
        "distance_km": 0.5,
        "rating": 4.5,
        "is_verified": true,
        "is_open_now": true,
        "products": [
          {
            "product_id": 1,
            "name": "Paracetamol 500mg",
            "price": 25.50,
            "is_available": true
          }
        ]
      }
    ],
    "pagination": { }
  }
}
```

---

## 20. Saved Item APIs

### 20.1 List Saved Products
- **Method:** `GET`
- **Path:** `/api/v1/saved-products`
- **Auth:** Bearer token required
- **Authorization:** Any authenticated user (self only)

**Query Parameters:**
| Param | Type | Required | Validation |
|---|---|---|---|
| `page` | int | No | Default 1 |
| `limit` | int | No | Default 20, max 100 |
| `sort` | string | No | `saved_at`, `-saved_at`, `lowest_price` |

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "items": [
      {
        "product_id": 1,
        "name": "Paracetamol 500mg",
        "brand": "Dabur",
        "lowest_price": 25.50,
        "image_url": "https://cdn.example.com/products/1.jpg",
        "saved_at": "2026-08-19T10:00:00Z"
      }
    ],
    "pagination": { }
  }
}
```

### 20.2 Save Product
- **Method:** `POST`
- **Path:** `/api/v1/saved-products/{product_id}`
- **Auth:** Bearer token required
- **Authorization:** Any authenticated user (self only)

**Response (200):**
```json
{
  "success": true,
  "message": "Product saved",
  "data": null
}
```

**Error Cases:**
| Status | Code | Condition |
|---|---|---|
| 404 | `PRODUCT_NOT_FOUND` | Product does not exist |
| 409 | `ALREADY_SAVED` | Product already saved |

**Idempotency:** Yes (re-saving is a no-op).

### 20.3 Unsave Product
- **Method:** `DELETE`
- **Path:** `/api/v1/saved-products/{product_id}`
- **Auth:** Bearer token required
- **Authorization:** Any authenticated user (self only)

**Error Cases:**
| Status | Code | Condition |
|---|---|---|
| 404 | `NOT_SAVED` | Product not in saved list |

**Idempotency:** Yes.

### 20.4 List Saved Shops
- **Method:** `GET`
- **Path:** `/api/v1/saved-shops`
- **Auth:** Bearer token required
- **Authorization:** Any authenticated user (self only)

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "items": [
      {
        "shop_id": 1,
        "name": "Patna Medical Store",
        "address": "Main Road, Patna",
        "image_url": "https://cdn.example.com/shops/1.jpg",
        "rating": 4.5,
        "saved_at": "2026-08-19T10:00:00Z"
      }
    ],
    "pagination": { }
  }
}
```

### 20.5 Save Shop
- **Method:** `POST`
- **Path:** `/api/v1/saved-shops/{shop_id}`
- **Auth:** Bearer token required
- **Authorization:** Any authenticated user (self only)

**Error Cases:**
| Status | Code | Condition |
|---|---|---|
| 404 | `SHOP_NOT_FOUND` | Shop does not exist |
| 409 | `ALREADY_SAVED` | Shop already saved |

**Idempotency:** Yes.

### 20.6 Unsave Shop
- **Method:** `DELETE`
- **Path:** `/api/v1/saved-shops/{shop_id}`
- **Auth:** Bearer token required
- **Authorization:** Any authenticated user (self only)

**Error Cases:**
| Status | Code | Condition |
|---|---|---|
| 404 | `NOT_SAVED` | Shop not in saved list |

**Idempotency:** Yes.

---

## 21. Notification APIs

### 21.1 List Notifications
- **Method:** `GET`
- **Path:** `/api/v1/notifications`
- **Auth:** Bearer token required
- **Authorization:** Any authenticated user (self only)

**Query Parameters:**
| Param | Type | Required | Validation |
|---|---|---|---|
| `page` | int | No | Default 1 |
| `limit` | int | No | Default 20, max 100 |
| `filter[is_read]` | boolean | No | Filter by read status |
| `filter[type]` | string | No | `order_update`, `price_alert`, `promotional`, `system` |

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "notifications": [
      {
        "id": 1,
        "title": "Price drop alert",
        "body": "Paracetamol 500mg is now ₹25.50 at Patna Medical Store",
        "type": "price_alert",
        "is_read": false,
        "payload": "{\"product_id\": 1, \"shop_id\": 1}",
        "created_at": "2026-08-19T10:00:00Z"
      }
    ],
    "unread_count": 3,
    "pagination": { }
  }
}
```

### 21.2 Mark Notification as Read
- **Method:** `PUT`
- **Path:** `/api/v1/notifications/{notification_id}/read`
- **Auth:** Bearer token required
- **Authorization:** Any authenticated user (self only)

**Error Cases:**
| Status | Code | Condition |
|---|---|---|
| 404 | `NOTIFICATION_NOT_FOUND` | Notification not found |

**Idempotency:** Yes.

### 21.3 Mark All Notifications as Read
- **Method:** `PUT`
- **Path:** `/api/v1/notifications/read-all`
- **Auth:** Bearer token required
- **Authorization:** Any authenticated user (self only)

**Idempotency:** Yes.

### 21.4 Get Notification Preferences
- **Method:** `GET`
- **Path:** `/api/v1/notifications/preferences`
- **Auth:** Bearer token required
- **Authorization:** Any authenticated user (self only)

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "push_enabled": true,
    "email_enabled": true,
    "sms_enabled": false,
    "price_alerts": true,
    "availability_alerts": true,
    "promotional": false,
    "deal_alerts": true
  }
}
```

### 21.5 Update Notification Preferences
- **Method:** `PUT`
- **Path:** `/api/v1/notifications/preferences`
- **Auth:** Bearer token required
- **Authorization:** Any authenticated user (self only)

**Request Body:**
```json
{
  "push_enabled": true,
  "email_enabled": true,
  "sms_enabled": false,
  "price_alerts": true,
  "availability_alerts": true,
  "promotional": false,
  "deal_alerts": true
}
```

**Idempotency:** Yes.

### 21.6 Register Device Token
- **Method:** `POST`
- **Path:** `/api/v1/notifications/device-token`
- **Auth:** Bearer token required
- **Authorization:** Any authenticated user (self only)

**Request Body:**
```json
{
  "token": "fcm_token_abc123",
  "device_type": "android",
  "platform": "FCM",
  "app_version": "1.0.0"
}
```

| Field | Type | Required | Validation |
|---|---|---|---|
| `token` | string | Yes | Max 500 chars |
| `device_type` | string | Yes | `android`, `ios`, `web` |
| `platform` | string | No | `FCM`, `APNS` |
| `app_version` | string | No | Max 20 chars |

**Idempotency:** Yes (re-registering same token is a no-op).

### 21.7 Unregister Device Token
- **Method:** `DELETE`
- **Path:** `/api/v1/notifications/device-token/{token}`
- **Auth:** Bearer token required
- **Authorization:** Any authenticated user (self only)

**Idempotency:** Yes.

---

## 22. Home Feed API

### 22.1 Get Home Feed
- **Method:** `GET`
- **Path:** `/api/v1/home/feed`
- **Auth:** None (public)

**Query Parameters:**
| Param | Type | Required | Validation |
|---|---|---|---|
| `latitude` | float | No | -90 to 90 |
| `longitude` | float | No | -180 to 180 |
| `radius_km` | float | No | 0.1 to 100, default 10.0 |

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "categories": [
      {
        "id": 1,
        "name": "Medicines",
        "icon_url": "https://cdn.example.com/icons/medicines.png"
      }
    ],
    "popular_products": [
      {
        "id": "1",
        "name": "Paracetamol 500mg",
        "brand": "Dabur",
        "image_url": "https://cdn.example.com/products/1.jpg",
        "price_range": "₹25 - ₹30"
      }
    ],
    "nearby_shops": [
      {
        "id": "1",
        "name": "Patna Medical Store",
        "image_url": "https://cdn.example.com/shops/1.jpg",
        "distance": 0.5,
        "rating": 4.5,
        "is_verified": true
      }
    ],
    "recent_searches": ["Paracetamol 500mg", "Amul Butter"]
  }
}
```

---

## 23. Shopkeeper APIs

All Shopkeeper endpoints require:
- **Auth:** Bearer token required
- **Authorization:** `SHOPKEEPER` role or higher
- **Ownership:** Shopkeeper must own or manage the shop

### 23.1 Shop Registration

#### 23.1.1 Register Shop
- **Method:** `POST`
- **Path:** `/api/v1/shopkeeper/shops`
- **Auth:** Bearer token required
- **Authorization:** `SHOPKEEPER` role

**Request Body:**
```json
{
  "name": "Patna Medical Store",
  "description": "Local medical store",
  "phone": "+919876543210",
  "email": "shop@example.com",
  "website_url": "https://example.com",
  "category": "MEDICAL",
  "latitude": 25.5941,
  "longitude": 85.1376,
  "address": {
    "address_line1": "Main Road",
    "address_line2": "Near Gandhi Maidan",
    "city": "Patna",
    "state": "Bihar",
    "pincode": "800001",
    "country": "India"
  },
  "opening_hours": [
    {
      "day_of_week": 0,
      "open_time": "09:00:00",
      "close_time": "21:00:00",
      "is_closed": false
    }
  ]
}
```

| Field | Type | Required | Validation |
|---|---|---|---|
| `name` | string | Yes | 1–255 chars |
| `description` | string | No | Max 5000 chars |
| `phone` | string | No | 10–20 chars |
| `email` | string | No | Valid email |
| `website_url` | string | No | Valid URL |
| `category` | string | No | Max 100 chars |
| `latitude` | float | Yes | -90 to 90 |
| `longitude` | float | Yes | -180 to 180 |
| `address.address_line1` | string | Yes | 1–255 chars |
| `address.city` | string | Yes | 1–100 chars |
| `address.state` | string | Yes | 1–100 chars |
| `address.pincode` | string | Yes | 6–10 chars |
| `opening_hours` | array | No | Max 7 entries |

**Response (201):**
```json
{
  "success": true,
  "message": "Shop registered successfully",
  "data": {
    "id": 1,
    "name": "Patna Medical Store",
    "status": "PENDING",
    "is_verified": false
  }
}
```

**Error Cases:**
| Status | Code | Condition |
|---|---|---|
| 400 | `VALIDATION_ERROR` | Invalid request body |
| 409 | `SHOP_ALREADY_REGISTERED` | User already has a shop with this name |
| 403 | `FORBIDDEN` | User is not a shopkeeper |

**Idempotency:** No (each call creates a new shop).

#### 23.1.2 Get My Shops
- **Method:** `GET`
- **Path:** `/api/v1/shopkeeper/shops`
- **Auth:** Bearer token required
- **Authorization:** `SHOPKEEPER` role

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "items": [
      {
        "id": 1,
        "name": "Patna Medical Store",
        "status": "PENDING",
        "is_verified": false,
        "rating": 0.0,
        "review_count": 0,
        "created_at": "2026-08-19T00:00:00Z"
      }
    ],
    "pagination": { }
  }
}
```

#### 23.1.3 Get Shop by ID (Shopkeeper)
- **Method:** `GET`
- **Path:** `/api/v1/shopkeeper/shops/{shop_id}`
- **Auth:** Bearer token required
- **Authorization:** `SHOPKEEPER` role, must own/manage shop

**Error Cases:**
| Status | Code | Condition |
|---|---|---|
| 404 | `SHOP_NOT_FOUND` | Shop does not exist |
| 403 | `FORBIDDEN` | User does not own/manage this shop |

#### 23.1.4 Update Shop
- **Method:** `PUT`
- **Path:** `/api/v1/shopkeeper/shops/{shop_id}`
- **Auth:** Bearer token required
- **Authorization:** `SHOPKEEPER` role, must own/manage shop

**Request Body:** Same as Register Shop (all fields optional for update).

**Idempotency:** Yes.

#### 23.1.5 Delete Shop
- **Method:** `DELETE`
- **Path:** `/api/v1/shopkeeper/shops/{shop_id}`
- **Auth:** Bearer token required
- **Authorization:** `SHOPKEEPER` role, must own shop (primary owner only)

**Idempotency:** Yes.

### 23.2 Shop Verification APIs

#### 23.2.1 Submit Shop for Verification
- **Method:** `POST`
- **Path:** `/api/v1/shopkeeper/shops/{shop_id}/verification`
- **Auth:** Bearer token required
- **Authorization:** `SHOPKEEPER` role, must own/manage shop

**Request Body:**
```json
{
  "documents": [
    {
      "document_type": "GST",
      "document_url": "https://cdn.example.com/docs/gst.pdf",
      "document_number": "GSTIN123456"
    },
    {
      "document_type": "LICENSE",
      "document_url": "https://cdn.example.com/docs/license.pdf",
      "document_number": "LIC123456"
    }
  ]
}
```

| Field | Type | Required | Validation |
|---|---|---|---|
| `documents` | array | Yes | 1–10 documents |
| `documents[].document_type` | string | Yes | `GST`, `LICENSE`, `PAN`, `FSSAI`, `OTHER` |
| `documents[].document_url` | string | Yes | Valid URL, max 500 chars |
| `documents[].document_number` | string | No | Max 100 chars |

**Response (200):**
```json
{
  "success": true,
  "message": "Verification submitted",
  "data": {
    "verification_id": 1,
    "status": "SUBMITTED",
    "submitted_at": "2026-08-19T10:00:00Z"
  }
}
```

**Error Cases:**
| Status | Code | Condition |
|---|---|---|
| 404 | `SHOP_NOT_FOUND` | Shop does not exist |
| 403 | `FORBIDDEN` | User does not own/manage shop |
| 409 | `CONFLICT` | Verification already in progress |

**Idempotency:** No (each submission creates a new verification record).

#### 23.2.2 Get Verification Status
- **Method:** `GET`
- **Path:** `/api/v1/shopkeeper/shops/{shop_id}/verification`
- **Auth:** Bearer token required
- **Authorization:** `SHOPKEEPER` role, must own/manage shop

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "verification_id": 1,
    "status": "UNDER_REVIEW",
    "submitted_at": "2026-08-19T10:00:00Z",
    "reviewed_at": null,
    "review_notes": null,
    "documents": [
      {
        "id": 1,
        "document_type": "GST",
        "document_url": "https://cdn.example.com/docs/gst.pdf",
        "is_verified": false
      }
    ]
  }
}
```

### 23.3 Product Inventory APIs (Shopkeeper)

#### 23.3.1 List Shop Inventory
- **Method:** `GET`
- **Path:** `/api/v1/shopkeeper/shops/{shop_id}/inventory`
- **Auth:** Bearer token required
- **Authorization:** `SHOPKEEPER` role, must own/manage shop

**Query Parameters:**
| Param | Type | Required | Validation |
|---|---|---|---|
| `page` | int | No | Default 1 |
| `limit` | int | No | Default 20, max 100 |
| `filter[in_stock]` | boolean | No | Only in-stock items |
| `filter[category_id]` | int | No | Filter by category |
| `sort` | string | No | `name`, `price`, `-price`, `quantity`, `-quantity` |

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "items": [
      {
        "shop_product_id": 1,
        "product_id": 1,
        "product_name": "Paracetamol 500mg",
        "product_image_url": "https://cdn.example.com/products/1.jpg",
        "price": 25.50,
        "mrp": 30.00,
        "quantity": 100,
        "reserved_quantity": 5,
        "available_quantity": 95,
        "is_available": true,
        "stock_status": "IN_STOCK",
        "low_stock_threshold": 10,
        "last_updated": "2026-08-19T10:00:00Z"
      }
    ],
    "pagination": { }
  }
}
```

#### 23.3.2 Add Product to Shop Inventory
- **Method:** `POST`
- **Path:** `/api/v1/shopkeeper/shops/{shop_id}/inventory`
- **Auth:** Bearer token required
- **Authorization:** `SHOPKEEPER` role, must own/manage shop

**Request Body:**
```json
{
  "product_master_id": 1,
  "variant_id": null,
  "price": 25.50,
  "mrp": 30.00,
  "quantity": 100,
  "low_stock_threshold": 10,
  "is_available": true
}
```

| Field | Type | Required | Validation |
|---|---|---|---|
| `product_master_id` | int | Yes | Positive integer |
| `variant_id` | int | No | Positive integer |
| `price` | float | Yes | >= 0 |
| `mrp` | float | No | >= 0, >= price |
| `quantity` | int | Yes | >= 0 |
| `low_stock_threshold` | int | No | >= 0 |
| `is_available` | boolean | No | Default true |

**Response (201):**
```json
{
  "success": true,
  "message": "Product added to inventory",
  "data": {
    "shop_product_id": 1,
    "product_id": 1,
    "price": 25.50,
    "quantity": 100,
    "is_available": true,
    "stock_status": "IN_STOCK"
  }
}
```

**Error Cases:**
| Status | Code | Condition |
|---|---|---|
| 404 | `PRODUCT_NOT_FOUND` | Product does not exist |
| 409 | `CONFLICT` | Product already in shop inventory |

**Idempotency:** No (use `PUT` for idempotent updates).

#### 23.3.3 Update Shop Inventory Item
- **Method:** `PUT`
- **Path:** `/api/v1/shopkeeper/shops/{shop_id}/inventory/{shop_product_id}`
- **Auth:** Bearer token required
- **Authorization:** `SHOPKEEPER` role, must own/manage shop

**Request Body:** Same as Add Product (all fields optional).

**Idempotency:** Yes.

#### 23.3.4 Update Stock Quantity
- **Method:** `PATCH`
- **Path:** `/api/v1/shopkeeper/shops/{shop_id}/inventory/{shop_product_id}/stock`
- **Auth:** Bearer token required
- **Authorization:** `SHOPKEEPER` role, must own/manage shop

**Request Body:**
```json
{
  "quantity": 95,
  "movement_type": "RESTOCK",
  "notes": "Restocked from supplier"
}
```

| Field | Type | Required | Validation |
|---|---|---|---|
| `quantity` | int | Yes | >= 0 |
| `movement_type` | string | Yes | `SALE`, `RESTOCK`, `RETURN`, `DAMAGE`, `ADJUSTMENT` |
| `notes` | string | No | Max 5000 chars |

**Idempotency:** No (each call records a movement).

#### 23.3.5 Update Price
- **Method:** `PATCH`
- **Path:** `/api/v1/shopkeeper/shops/{shop_id}/inventory/{shop_product_id}/price`
- **Auth:** Bearer token required
- **Authorization:** `SHOPKEEPER` role, must own/manage shop

**Request Body:**
```json
{
  "price": 24.00,
  "mrp": 30.00
}
```

| Field | Type | Required | Validation |
|---|---|---|---|
| `price` | float | Yes | >= 0 |
| `mrp` | float | No | >= 0, >= price |

**Idempotency:** Yes.

#### 23.3.6 Remove Product from Inventory
- **Method:** `DELETE`
- **Path:** `/api/v1/shopkeeper/shops/{shop_id}/inventory/{shop_product_id}`
- **Auth:** Bearer token required
- **Authorization:** `SHOPKEEPER` role, must own/manage shop

**Idempotency:** Yes.

### 23.4 Barcode APIs (Shopkeeper)

#### 23.4.1 Scan Barcode
- **Method:** `POST`
- **Path:** `/api/v1/shopkeeper/barcode/scan`
- **Auth:** Bearer token required
- **Authorization:** `SHOPKEEPER` role

**Request Body:**
```json
{
  "barcode": "8901234567890",
  "barcode_type": "EAN-13",
  "shop_id": 1
}
```

| Field | Type | Required | Validation |
|---|---|---|---|
| `barcode` | string | Yes | 8–100 chars |
| `barcode_type` | string | No | `EAN-13`, `UPC-A`, `QR`, `OTHER` |
| `shop_id` | int | Yes | Positive integer |

**Response (200):**
```json
{
  "success": true,
  "message": "Barcode scanned",
  "data": {
    "barcode": "8901234567890",
    "is_match_found": true,
    "product": {
      "id": 1,
      "name": "Paracetamol 500mg",
      "brand": "Dabur",
      "category": "Medicines",
      "image_url": "https://cdn.example.com/products/1.jpg"
    },
    "in_shop_inventory": true,
    "shop_product_id": 1,
    "current_price": 25.50,
    "current_quantity": 100
  }
}
```

**Error Cases:**
| Status | Code | Condition |
|---|---|---|
| 404 | `PRODUCT_NOT_FOUND` | No product matches barcode |
| 403 | `FORBIDDEN` | User does not own/manage shop |

**Idempotency:** No (records a scan event).

#### 23.4.2 Get Barcode Scan History
- **Method:** `GET`
- **Path:** `/api/v1/shopkeeper/barcode/history`
- **Auth:** Bearer token required
- **Authorization:** `SHOPKEEPER` role

**Query Parameters:**
| Param | Type | Required | Validation |
|---|---|---|---|
| `shop_id` | int | No | Filter by shop |
| `page` | int | No | Default 1 |
| `limit` | int | No | Default 20, max 100 |

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "items": [
      {
        "id": 1,
        "barcode": "8901234567890",
        "barcode_type": "EAN-13",
        "is_match_found": true,
        "product_id": 1,
        "product_name": "Paracetamol 500mg",
        "scan_time": "2026-08-19T10:00:00Z"
      }
    ],
    "pagination": { }
  }
}
```

### 23.5 Excel Import APIs

#### 23.5.1 Upload Excel Inventory
- **Method:** `POST`
- **Path:** `/api/v1/shopkeeper/shops/{shop_id}/inventory/import`
- **Auth:** Bearer token required
- **Authorization:** `SHOPKEEPER` role, must own/manage shop
- **Content-Type:** `multipart/form-data`

**Request Body:**
| Field | Type | Required | Validation |
|---|---|---|---|
| `file` | file | Yes | `.xlsx`, `.xls`, `.csv`, max 10 MB |
| `source` | string | No | `EXCEL_UPLOAD` (default) |

**Response (202):**
```json
{
  "success": true,
  "message": "Import started",
  "data": {
    "import_id": 1,
    "status": "PROCESSING",
    "total_rows": 100,
    "processed_rows": 0,
    "failed_rows": 0
  }
}
```

**Error Cases:**
| Status | Code | Condition |
|---|---|---|
| 400 | `VALIDATION_ERROR` | Invalid file format |
| 413 | `PAYLOAD_TOO_LARGE` | File exceeds 10 MB |

**Idempotency:** No (each upload creates a new import job).

#### 23.5.2 Get Import Status
- **Method:** `GET`
- **Path:** `/api/v1/shopkeeper/inventory/imports/{import_id}`
- **Auth:** Bearer token required
- **Authorization:** `SHOPKEEPER` role, must own/manage shop

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "import_id": 1,
    "status": "COMPLETED",
    "total_rows": 100,
    "processed_rows": 100,
    "succeeded_rows": 95,
    "failed_rows": 5,
    "errors": [
      {
        "row": 10,
        "error": "Invalid price: must be >= 0"
      }
    ],
    "completed_at": "2026-08-19T10:05:00Z"
  }
}
```

### 23.6 POS Integration APIs

#### 23.6.1 Create POS Integration
- **Method:** `POST`
- **Path:** `/api/v1/shopkeeper/shops/{shop_id}/pos-integrations`
- **Auth:** Bearer token required
- **Authorization:** `SHOPKEEPER` role, must own/manage shop

**Request Body:**
```json
{
  "provider_name": "Marg",
  "integration_type": "API",
  "api_base_url": "https://pos.example.com/api",
  "api_key": "encrypted_key",
  "api_secret": "encrypted_secret",
  "config": {
    "sync_interval_minutes": 30
  }
}
```

| Field | Type | Required | Validation |
|---|---|---|---|
| `provider_name` | string | Yes | 1–100 chars |
| `integration_type` | string | Yes | `API`, `FILE_UPLOAD`, `WEBHOOK` |
| `api_base_url` | string | No | Valid URL |
| `api_key` | string | No | Max 500 chars |
| `api_secret` | string | No | Max 500 chars |
| `config` | object | No | JSON object |

**Response (201):**
```json
{
  "success": true,
  "message": "POS integration created",
  "data": {
    "id": 1,
    "provider_name": "Marg",
    "integration_type": "API",
    "status": "ACTIVE"
  }
}
```

**Idempotency:** No.

#### 23.6.2 List POS Integrations
- **Method:** `GET`
- **Path:** `/api/v1/shopkeeper/shops/{shop_id}/pos-integrations`
- **Auth:** Bearer token required
- **Authorization:** `SHOPKEEPER` role, must own/manage shop

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "items": [
      {
        "id": 1,
        "provider_name": "Marg",
        "integration_type": "API",
        "status": "ACTIVE",
        "last_sync_at": "2026-08-19T10:00:00Z",
        "last_sync_status": "COMPLETED"
      }
    ],
    "pagination": { }
  }
}
```

#### 23.6.3 Trigger POS Sync
- **Method:** `POST`
- **Path:** `/api/v1/shopkeeper/shops/{shop_id}/pos-integrations/{integration_id}/sync`
- **Auth:** Bearer token required
- **Authorization:** `SHOPKEEPER` role, must own/manage shop

**Request Body:**
```json
{
  "sync_type": "FULL"
}
```

| Field | Type | Required | Validation |
|---|---|---|---|
| `sync_type` | string | Yes | `INVENTORY`, `PRICE`, `PRODUCT`, `FULL` |

**Response (202):**
```json
{
  "success": true,
  "message": "Sync started",
  "data": {
    "sync_job_id": 1,
    "status": "PENDING",
    "sync_type": "FULL"
  }
}
```

**Idempotency:** No.

#### 23.6.4 Get POS Sync Status
- **Method:** `GET`
- **Path:** `/api/v1/shopkeeper/pos-sync-jobs/{sync_job_id}`
- **Auth:** Bearer token required
- **Authorization:** `SHOPKEEPER` role, must own/manage shop

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "sync_job_id": 1,
    "sync_type": "FULL",
    "status": "COMPLETED",
    "items_processed": 100,
    "items_succeeded": 98,
    "items_failed": 2,
    "error_summary": "2 items failed: invalid barcode",
    "started_at": "2026-08-19T10:00:00Z",
    "completed_at": "2026-08-19T10:05:00Z"
  }
}
```

#### 23.6.5 List POS Sync Jobs
- **Method:** `GET`
- **Path:** `/api/v1/shopkeeper/shops/{shop_id}/pos-sync-jobs`
- **Auth:** Bearer token required
- **Authorization:** `SHOPKEEPER` role, must own/manage shop

**Query Parameters:**
| Param | Type | Required | Validation |
|---|---|---|---|
| `page` | int | No | Default 1 |
| `limit` | int | No | Default 20, max 100 |
| `filter[status]` | string | No | `PENDING`, `RUNNING`, `COMPLETED`, `FAILED` |

---

## 24. Admin APIs

All Admin endpoints require:
- **Auth:** Bearer token required
- **Authorization:** `ADMIN` or `SUPER_ADMIN` role

### 24.1 Shop Management

#### 24.1.1 List All Shops
- **Method:** `GET`
- **Path:** `/api/v1/admin/shops`
- **Auth:** Bearer token required
- **Authorization:** `ADMIN` or `SUPER_ADMIN`

**Query Parameters:**
| Param | Type | Required | Validation |
|---|---|---|---|
| `page` | int | No | Default 1 |
| `limit` | int | No | Default 20, max 100 |
| `filter[status]` | string | No | `PENDING`, `ACTIVE`, `SUSPENDED`, `CLOSED`, `REJECTED` |
| `filter[is_verified]` | boolean | No | Filter by verification status |
| `filter[city]` | string | No | Filter by city |
| `sort` | string | No | `name`, `-name`, `created_at`, `-created_at`, `rating`, `-rating` |

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "items": [
      {
        "id": 1,
        "name": "Patna Medical Store",
        "status": "PENDING",
        "is_verified": false,
        "rating": 0.0,
        "review_count": 0,
        "phone": "+919876543210",
        "city": "Patna",
        "created_at": "2026-08-19T00:00:00Z"
      }
    ],
    "pagination": { }
  }
}
```

#### 24.1.2 Get Shop Detail (Admin)
- **Method:** `GET`
- **Path:** `/api/v1/admin/shops/{shop_id}`
- **Auth:** Bearer token required
- **Authorization:** `ADMIN` or `SUPER_ADMIN`

**Response (200):** Full shop detail including owners, documents, verification status.

#### 24.1.3 Approve Shop
- **Method:** `POST`
- **Path:** `/api/v1/admin/shops/{shop_id}/approve`
- **Auth:** Bearer token required
- **Authorization:** `ADMIN` or `SUPER_ADMIN`

**Request Body:**
```json
{
  "notes": "All documents verified"
}
```

**Response (200):**
```json
{
  "success": true,
  "message": "Shop approved",
  "data": {
    "shop_id": 1,
    "status": "ACTIVE",
    "is_verified": true,
    "verified_at": "2026-08-19T10:00:00Z"
  }
}
```

**Idempotency:** Yes (approving an approved shop is a no-op).

#### 24.1.4 Reject Shop
- **Method:** `POST`
- **Path:** `/api/v1/admin/shops/{shop_id}/reject`
- **Auth:** Bearer token required
- **Authorization:** `ADMIN` or `SUPER_ADMIN`

**Request Body:**
```json
{
  "reason": "Invalid GST document"
}
```

| Field | Type | Required | Validation |
|---|---|---|---|
| `reason` | string | Yes | 1–5000 chars |

**Idempotency:** Yes.

#### 24.1.5 Suspend Shop
- **Method:** `POST`
- **Path:** `/api/v1/admin/shops/{shop_id}/suspend`
- **Auth:** Bearer token required
- **Authorization:** `ADMIN` or `SUPER_ADMIN`

**Request Body:**
```json
{
  "reason": "Multiple customer complaints"
}
```

**Idempotency:** Yes.

#### 24.1.6 Reactivate Shop
- **Method:** `POST`
- **Path:** `/api/v1/admin/shops/{shop_id}/reactivate`
- **Auth:** Bearer token required
- **Authorization:** `ADMIN` or `SUPER_ADMIN`

**Idempotency:** Yes.

### 24.2 Shop Verification Management

#### 24.2.1 List Shop Verifications
- **Method:** `GET`
- **Path:** `/api/v1/admin/verifications`
- **Auth:** Bearer token required
- **Authorization:** `ADMIN` or `SUPER_ADMIN`

**Query Parameters:**
| Param | Type | Required | Validation |
|---|---|---|---|
| `page` | int | No | Default 1 |
| `limit` | int | No | Default 20, max 100 |
| `filter[status]` | string | No | `PENDING`, `SUBMITTED`, `UNDER_REVIEW`, `VERIFIED`, `REJECTED`, `EXPIRED` |

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "items": [
      {
        "id": 1,
        "shop_id": 1,
        "shop_name": "Patna Medical Store",
        "status": "SUBMITTED",
        "submitted_at": "2026-08-19T10:00:00Z",
        "documents": [
          {
            "id": 1,
            "document_type": "GST",
            "document_url": "https://cdn.example.com/docs/gst.pdf",
            "is_verified": false
          }
        ]
      }
    ],
    "pagination": { }
  }
}
```

#### 24.2.2 Review Verification
- **Method:** `POST`
- **Path:** `/api/v1/admin/verifications/{verification_id}/review`
- **Auth:** Bearer token required
- **Authorization:** `ADMIN` or `SUPER_ADMIN`

**Request Body:**
```json
{
  "decision": "APPROVED",
  "notes": "All documents verified",
  "document_verifications": [
    {
      "document_id": 1,
      "is_verified": true
    }
  ]
}
```

| Field | Type | Required | Validation |
|---|---|---|---|
| `decision` | string | Yes | `APPROVED`, `REJECTED`, `NEEDS_INFO` |
| `notes` | string | No | Max 5000 chars |
| `document_verifications` | array | No | Document-level verification |

**Idempotency:** No (each review creates an action log).

### 24.3 Product Approval Management

#### 24.3.1 List Product Approvals
- **Method:** `GET`
- **Path:** `/api/v1/admin/product-approvals`
- **Auth:** Bearer token required
- **Authorization:** `ADMIN` or `SUPER_ADMIN`

**Query Parameters:**
| Param | Type | Required | Validation |
|---|---|---|---|
| `page` | int | No | Default 1 |
| `limit` | int | No | Default 20, max 100 |
| `filter[status]` | string | No | `PENDING`, `APPROVED`, `REJECTED`, `NEEDS_INFO` |

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "items": [
      {
        "id": 1,
        "product_master_id": 1,
        "product_name": "Paracetamol 500mg",
        "shop_id": 1,
        "shop_name": "Patna Medical Store",
        "status": "PENDING",
        "submitted_at": "2026-08-19T10:00:00Z",
        "submission_data": { }
      }
    ],
    "pagination": { }
  }
}
```

#### 24.3.2 Review Product Approval
- **Method:** `POST`
- **Path:** `/api/v1/admin/product-approvals/{approval_id}/review`
- **Auth:** Bearer token required
- **Authorization:** `ADMIN` or `SUPER_ADMIN`

**Request Body:**
```json
{
  "decision": "APPROVED",
  "notes": "Product details verified"
}
```

| Field | Type | Required | Validation |
|---|---|---|---|
| `decision` | string | Yes | `APPROVED`, `REJECTED`, `NEEDS_INFO` |
| `notes` | string | No | Max 5000 chars |

### 24.4 User Management

#### 24.4.1 List Users
- **Method:** `GET`
- **Path:** `/api/v1/admin/users`
- **Auth:** Bearer token required
- **Authorization:** `ADMIN` or `SUPER_ADMIN`

**Query Parameters:**
| Param | Type | Required | Validation |
|---|---|---|---|
| `page` | int | No | Default 1 |
| `limit` | int | No | Default 20, max 100 |
| `filter[status]` | string | No | `ACTIVE`, `INACTIVE`, `SUSPENDED`, `BANNED` |
| `filter[role]` | string | No | `CUSTOMER`, `SHOPKEEPER`, `ADMIN` |
| `filter[phone_number]` | string | No | Partial match |
| `sort` | string | No | `created_at`, `-created_at`, `name`, `-name` |

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "items": [
      {
        "id": 1,
        "name": "John Doe",
        "phone_number": "+919876543210",
        "email": "john@example.com",
        "role": "CUSTOMER",
        "status": "ACTIVE",
        "is_active": true,
        "created_at": "2026-01-01T00:00:00Z"
      }
    ],
    "pagination": { }
  }
}
```

#### 24.4.2 Get User Detail (Admin)
- **Method:** `GET`
- **Path:** `/api/v1/admin/users/{user_id}`
- **Auth:** Bearer token required
- **Authorization:** `ADMIN` or `SUPER_ADMIN`

#### 24.4.3 Suspend User
- **Method:** `POST`
- **Path:** `/api/v1/admin/users/{user_id}/suspend`
- **Auth:** Bearer token required
- **Authorization:** `ADMIN` or `SUPER_ADMIN`

**Request Body:**
```json
{
  "reason": "Violation of terms"
}
```

**Idempotency:** Yes.

#### 24.4.4 Ban User
- **Method:** `POST`
- **Path:** `/api/v1/admin/users/{user_id}/ban`
- **Auth:** Bearer token required
- **Authorization:** `SUPER_ADMIN` only

**Request Body:**
```json
{
  "reason": "Fraudulent activity"
}
```

**Idempotency:** Yes.

#### 24.4.5 Reactivate User
- **Method:** `POST`
- **Path:** `/api/v1/admin/users/{user_id}/reactivate`
- **Auth:** Bearer token required
- **Authorization:** `ADMIN` or `SUPER_ADMIN`

**Idempotency:** Yes.

### 24.5 Subscription Management

#### 24.5.1 List Subscriptions
- **Method:** `GET`
- **Path:** `/api/v1/admin/subscriptions`
- **Auth:** Bearer token required
- **Authorization:** `ADMIN` or `SUPER_ADMIN`

**Query Parameters:**
| Param | Type | Required | Validation |
|---|---|---|---|
| `page` | int | No | Default 1 |
| `limit` | int | No | Default 20, max 100 |
| `filter[status]` | string | No | `ACTIVE`, `PAST_DUE`, `CANCELED`, `TRIALING`, `INCOMPLETE` |
| `filter[plan_id]` | int | No | Filter by plan |

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "items": [
      {
        "id": 1,
        "user_id": 1,
        "user_name": "John Doe",
        "shop_id": 1,
        "shop_name": "Patna Medical Store",
        "plan_id": 1,
        "plan_name": "Pro",
        "status": "ACTIVE",
        "is_auto_renew": true,
        "current_period_start": "2026-08-01T00:00:00Z",
        "current_period_end": "2026-08-31T23:59:59Z",
        "trial_ends_at": null
      }
    ],
    "pagination": { }
  }
}
```

#### 24.5.2 List Subscription Plans
- **Method:** `GET`
- **Path:** `/api/v1/admin/subscription-plans`
- **Auth:** Bearer token required
- **Authorization:** `ADMIN` or `SUPER_ADMIN`

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "items": [
      {
        "id": 1,
        "name": "Free",
        "description": "Basic features",
        "price_monthly": 0.0,
        "price_annual": 0.0,
        "currency": "INR",
        "billing_cycle": "MONTHLY",
        "is_active": true,
        "features": { "unlimited_scans": 10 },
        "max_shops": 1,
        "max_products": 100,
        "trial_days": 0
      }
    ],
    "pagination": { }
  }
}
```

#### 24.5.3 Create Subscription Plan
- **Method:** `POST`
- **Path:** `/api/v1/admin/subscription-plans`
- **Auth:** Bearer token required
- **Authorization:** `SUPER_ADMIN` only

**Request Body:**
```json
{
  "name": "Pro",
  "description": "For growing shops",
  "price_monthly": 499.0,
  "price_annual": 4990.0,
  "currency": "INR",
  "billing_cycle": "MONTHLY",
  "features": { "unlimited_scans": 1000 },
  "max_shops": 3,
  "max_products": 5000,
  "trial_days": 14
}
```

**Idempotency:** No.

#### 24.5.4 Update Subscription Plan
- **Method:** `PUT`
- **Path:** `/api/v1/admin/subscription-plans/{plan_id}`
- **Auth:** Bearer token required
- **Authorization:** `SUPER_ADMIN` only

**Idempotency:** Yes.

#### 24.5.5 Cancel Subscription
- **Method:** `POST`
- **Path:** `/api/v1/admin/subscriptions/{subscription_id}/cancel`
- **Auth:** Bearer token required
- **Authorization:** `ADMIN` or `SUPER_ADMIN`

**Request Body:**
```json
{
  "reason": "Customer requested cancellation"
}
```

**Idempotency:** Yes.

### 24.6 Complaint Management

#### 24.6.1 List Complaints
- **Method:** `GET`
- **Path:** `/api/v1/admin/complaints`
- **Auth:** Bearer token required
- **Authorization:** `ADMIN` or `SUPER_ADMIN`

**Query Parameters:**
| Param | Type | Required | Validation |
|---|---|---|---|
| `page` | int | No | Default 1 |
| `limit` | int | No | Default 20, max 100 |
| `filter[status]` | string | No | `OPEN`, `IN_PROGRESS`, `RESOLVED`, `CLOSED`, `REJECTED` |
| `filter[priority]` | string | No | `LOW`, `MEDIUM`, `HIGH`, `URGENT` |
| `filter[complaint_type]` | string | No | `WRONG_PRICE`, `FAKE_PRODUCT`, `SHOP_ISSUE` |

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "items": [
      {
        "id": 1,
        "complaint_type": "WRONG_PRICE",
        "subject": "Price mismatch",
        "description": "Product was priced higher than displayed",
        "entity_type": "SHOP",
        "entity_id": 1,
        "status": "OPEN",
        "priority": "HIGH",
        "complainant_user_id": 1,
        "created_at": "2026-08-19T10:00:00Z"
      }
    ],
    "pagination": { }
  }
}
```

#### 24.6.2 Get Complaint Detail
- **Method:** `GET`
- **Path:** `/api/v1/admin/complaints/{complaint_id}`
- **Auth:** Bearer token required
- **Authorization:** `ADMIN` or `SUPER_ADMIN`

#### 24.6.3 Update Complaint Status
- **Method:** `PATCH`
- **Path:** `/api/v1/admin/complaints/{complaint_id}`
- **Auth:** Bearer token required
- **Authorization:** `ADMIN` or `SUPER_ADMIN`

**Request Body:**
```json
{
  "status": "IN_PROGRESS",
  "priority": "URGENT",
  "assigned_to": 2,
  "resolution_notes": "Investigating"
}
```

| Field | Type | Required | Validation |
|---|---|---|---|
| `status` | string | No | `OPEN`, `IN_PROGRESS`, `RESOLVED`, `CLOSED`, `REJECTED` |
| `priority` | string | No | `LOW`, `MEDIUM`, `HIGH`, `URGENT` |
| `assigned_to` | int | No | Admin user ID |
| `resolution_notes` | string | No | Max 5000 chars |

**Idempotency:** Yes.

### 24.7 Analytics APIs

#### 24.7.1 Get Dashboard Analytics
- **Method:** `GET`
- **Path:** `/api/v1/admin/analytics/dashboard`
- **Auth:** Bearer token required
- **Authorization:** `ADMIN` or `SUPER_ADMIN`

**Query Parameters:**
| Param | Type | Required | Validation |
|---|---|---|---|
| `from` | datetime | No | Start date |
| `to` | datetime | No | End date |

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "total_users": 1000,
    "total_shops": 50,
    "total_products": 5000,
    "total_searches": 10000,
    "active_users_today": 200,
    "new_users_today": 10,
    "new_shops_today": 2,
    "total_orders": 500,
    "revenue": 250000.00
  }
}
```

#### 24.7.2 Get Product Analytics
- **Method:** `GET`
- **Path:** `/api/v1/admin/analytics/products`
- **Auth:** Bearer token required
- **Authorization:** `ADMIN` or `SUPER_ADMIN`

**Query Parameters:**
| Param | Type | Required | Validation |
|---|---|---|---|
| `from` | datetime | No | Start date |
| `to` | datetime | No | End date |
| `page` | int | No | Default 1 |
| `limit` | int | No | Default 20, max 100 |
| `sort` | string | No | `views`, `-views`, `clicks`, `-clicks` |

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "items": [
      {
        "product_id": 1,
        "product_name": "Paracetamol 500mg",
        "views": 1000,
        "clicks": 500,
        "click_through_rate": 0.5,
        "saved_count": 100
      }
    ],
    "pagination": { }
  }
}
```

#### 24.7.3 Get Shop Analytics
- **Method:** `GET`
- **Path:** `/api/v1/admin/analytics/shops`
- **Auth:** Bearer token required
- **Authorization:** `ADMIN` or `SUPER_ADMIN`

**Query Parameters:**
| Param | Type | Required | Validation |
|---|---|---|---|
| `from` | datetime | No | Start date |
| `to` | datetime | No | End date |
| `page` | int | No | Default 1 |
| `limit` | int | No | Default 20, max 100 |
| `sort` | string | No | `views`, `-views`, `rating`, `-rating` |

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "items": [
      {
        "shop_id": 1,
        "shop_name": "Patna Medical Store",
        "views": 500,
        "rating": 4.5,
        "review_count": 120,
        "product_count": 100,
        "inventory_update_count": 50
      }
    ],
    "pagination": { }
  }
}
```

#### 24.7.4 Get Search Analytics
- **Method:** `GET`
- **Path:** `/api/v1/admin/analytics/search`
- **Auth:** Bearer token required
- **Authorization:** `ADMIN` or `SUPER_ADMIN`

**Query Parameters:**
| Param | Type | Required | Validation |
|---|---|---|---|
| `from` | datetime | No | Start date |
| `to` | datetime | No | End date |
| `page` | int | No | Default 1 |
| `limit` | int | No | Default 20, max 100 |

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "items": [
      {
        "query": "Paracetamol",
        "search_count": 1000,
        "result_count": 50,
        "success_rate": 0.95
      }
    ],
    "pagination": { }
  }
}
```

### 24.8 Report APIs

#### 24.8.1 Generate Report
- **Method:** `POST`
- **Path:** `/api/v1/admin/reports`
- **Auth:** Bearer token required
- **Authorization:** `ADMIN` or `SUPER_ADMIN`

**Request Body:**
```json
{
  "report_type": "SALES",
  "report_name": "August Sales Report",
  "parameters": {
    "from": "2026-08-01T00:00:00Z",
    "to": "2026-08-31T23:59:59Z"
  }
}
```

| Field | Type | Required | Validation |
|---|---|---|---|
| `report_type` | string | Yes | `SALES`, `INVENTORY`, `SEARCH_ANALYTICS`, `USER_ACTIVITY` |
| `report_name` | string | Yes | 1–255 chars |
| `parameters` | object | No | JSON object |

**Response (202):**
```json
{
  "success": true,
  "message": "Report generation started",
  "data": {
    "report_id": 1,
    "status": "PENDING",
    "report_type": "SALES",
    "report_name": "August Sales Report"
  }
}
```

**Idempotency:** No.

#### 24.8.2 Get Report Status
- **Method:** `GET`
- **Path:** `/api/v1/admin/reports/{report_id}`
- **Auth:** Bearer token required
- **Authorization:** `ADMIN` or `SUPER_ADMIN`

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "report_id": 1,
    "report_type": "SALES",
    "report_name": "August Sales Report",
    "status": "READY",
    "file_url": "https://cdn.example.com/reports/1.xlsx",
    "started_at": "2026-08-19T10:00:00Z",
    "completed_at": "2026-08-19T10:01:00Z"
  }
}
```

#### 24.8.3 List Reports
- **Method:** `GET`
- **Path:** `/api/v1/admin/reports`
- **Auth:** Bearer token required
- **Authorization:** `ADMIN` or `SUPER_ADMIN`

**Query Parameters:**
| Param | Type | Required | Validation |
|---|---|---|---|
| `page` | int | No | Default 1 |
| `limit` | int | No | Default 20, max 100 |
| `filter[report_type]` | string | No | Filter by report type |
| `filter[status]` | string | No | `PENDING`, `GENERATING`, `READY`, `FAILED` |

---

#### 24.9 Admin Catalog Management (Categories & Brands)

All endpoints below require a Bearer token and the documented admin
permission resource/action. The permission catalog is enforced server-side
via `require_admin_permission(resource, action)`.

| Resource | Action | Permission key |
|---|---|---|
| List categories | `category:read` | `GET /api/v1/admin/categories` |
| Create category | `category:create` | `POST /api/v1/admin/categories` |
| Update category | `category:update` | `PUT /api/v1/admin/categories/{category_id}` |
| Delete category (soft) | `category:delete` | `DELETE /api/v1/admin/categories/{category_id}` |
| List brands | `brand:read` | `GET /api/v1/admin/brands` |
| Create brand | `brand:create` | `POST /api/v1/admin/brands` |
| Update brand | `brand:update` | `PUT /api/v1/admin/brands/{brand_id}` |
| Delete brand (soft) | `brand:delete` | `DELETE /api/v1/admin/brands/{brand_id}` |

##### 24.9.1 Create Brand
- **Method:** `POST`
- **Path:** `/api/v1/admin/brands`
- **Auth:** Bearer token required
- **Authorization:** `brand:create`

**Request Body:**
```json
{
  "name": "Nestle",
  "slug": "nestle",
  "description": "fmcg",
  "logo_url": "https://cdn.example.com/logos/nestle.png",
  "is_active": true
}
```

**Response (201):**
```json
{
  "success": true,
  "message": "Brand created",
  "data": { "id": 1, "name": "Nestle", "slug": "nestle", "is_active": true }
}
```

**Error Cases:**
| Status | Code | Condition |
|---|---|---|
| 403 | `FORBIDDEN` | Caller lacks `brand:create` |
| 409 | `CONFLICT` | Brand name or slug already exists |

##### 24.9.2 Update Brand
- **Method:** `PUT`
- **Path:** `/api/v1/admin/brands/{brand_id}`
- **Auth:** Bearer token required
- **Authorization:** `brand:update`

**Request Body:** optional subset of `{name, slug, description, logo_url, is_active}`.

**Response (200):** updated brand object.

##### 24.9.3 Delete Brand
- **Method:** `DELETE`
- **Path:** `/api/v1/admin/brands/{brand_id}`
- **Auth:** Bearer token required
- **Authorization:** `brand:delete`

**Behavior:** soft-deletes the brand (`is_deleted = true`). Blocked with
`409 CONFLICT` while active products still reference the brand. Every
create/update/delete writes an immutable `AuditLog` record.

**Response (200):**
```json
{
  "success": true,
  "message": "Brand deleted",
  "data": { "id": 1, "deleted": true }
}
```

**Error Cases:**
| Status | Code | Condition |
|---|---|---|
| 403 | `FORBIDDEN` | Caller lacks `brand:delete` |
| 404 | `NOT_FOUND` | Brand does not exist or already deleted |
| 409 | `CONFLICT` | Active products still reference the brand |

---

## 25. Subscription APIs (Shopkeeper)

### 25.1 Get Current Subscription
- **Method:** `GET`
- **Path:** `/api/v1/shopkeeper/subscription`
- **Auth:** Bearer token required
- **Authorization:** `SHOPKEEPER` role

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "id": 1,
    "plan_id": 1,
    "plan_name": "Pro",
    "status": "ACTIVE",
    "is_auto_renew": true,
    "current_period_start": "2026-08-01T00:00:00Z",
    "current_period_end": "2026-08-31T23:59:59Z",
    "trial_ends_at": null,
    "features": { "unlimited_scans": 1000 }
  }
}
```

### 25.2 List Available Plans
- **Method:** `GET`
- **Path:** `/api/v1/shopkeeper/subscription/plans`
- **Auth:** Bearer token required
- **Authorization:** `SHOPKEEPER` role

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "items": [
      {
        "id": 1,
        "name": "Free",
        "description": "Basic features",
        "price_monthly": 0.0,
        "price_annual": 0.0,
        "currency": "INR",
        "billing_cycle": "MONTHLY",
        "features": { "unlimited_scans": 10 },
        "max_shops": 1,
        "max_products": 100,
        "trial_days": 0
      }
    ],
    "pagination": { }
  }
}
```

### 25.3 Subscribe to Plan
- **Method:** `POST`
- **Path:** `/api/v1/shopkeeper/subscription/subscribe`
- **Auth:** Bearer token required
- **Authorization:** `SHOPKEEPER` role

**Request Body:**
```json
{
  "plan_id": 2,
  "billing_cycle": "MONTHLY",
  "is_auto_renew": true
}
```

| Field | Type | Required | Validation |
|---|---|---|---|
| `plan_id` | int | Yes | Positive integer |
| `billing_cycle` | string | Yes | `WEEKLY`, `MONTHLY`, `QUARTERLY`, `ANNUAL` |
| `is_auto_renew` | boolean | No | Default true |

**Response (201):**
```json
{
  "success": true,
  "message": "Subscription created",
  "data": {
    "subscription_id": 1,
    "plan_id": 2,
    "status": "ACTIVE",
    "current_period_start": "2026-08-19T00:00:00Z",
    "current_period_end": "2026-09-18T23:59:59Z"
  }
}
```

**Idempotency:** No.

### 25.4 Cancel Subscription
- **Method:** `POST`
- **Path:** `/api/v1/shopkeeper/subscription/cancel`
- **Auth:** Bearer token required
- **Authorization:** `SHOPKEEPER` role

**Request Body:**
```json
{
  "reason": "Not needed anymore"
}
```

**Idempotency:** Yes.

---

## 26. Payment APIs

### 26.1 Create Payment Intent
- **Method:** `POST`
- **Path:** `/api/v1/payments/create-intent`
- **Auth:** Bearer token required
- **Authorization:** `SHOPKEEPER` role

**Request Body:**
```json
{
  "subscription_id": 1,
  "amount": 499.00,
  "currency": "INR",
  "payment_method": "UPI"
}
```

| Field | Type | Required | Validation |
|---|---|---|---|
| `subscription_id` | int | Yes | Positive integer |
| `amount` | float | Yes | > 0 |
| `currency` | string | No | Default `INR` |
| `payment_method` | string | Yes | `CARD`, `UPI`, `NETBANKING`, `WALLET` |

**Response (200):**
```json
{
  "success": true,
  "message": "Payment intent created",
  "data": {
    "payment_id": 1,
    "provider": "RAZORPAY",
    "provider_order_id": "order_abc123",
    "amount": 499.00,
    "currency": "INR",
    "status": "PENDING"
  }
}
```

**Idempotency:** No.

### 26.2 Verify Payment
- **Method:** `POST`
- **Path:** `/api/v1/payments/verify`
- **Auth:** Bearer token required
- **Authorization:** `SHOPKEEPER` role

**Request Body:**
```json
{
  "payment_id": 1,
  "provider_payment_id": "pay_abc123",
  "provider_signature": "sig_abc123"
}
```

| Field | Type | Required | Validation |
|---|---|---|---|
| `payment_id` | int | Yes | Positive integer |
| `provider_payment_id` | string | Yes | Max 255 chars |
| `provider_signature` | string | Yes | Max 255 chars |

**Response (200):**
```json
{
  "success": true,
  "message": "Payment verified",
  "data": {
    "payment_id": 1,
    "status": "SUCCESS",
    "paid_at": "2026-08-19T10:00:00Z"
  }
}
```

**Error Cases:**
| Status | Code | Condition |
|---|---|---|
| 400 | `VALIDATION_ERROR` | Invalid signature |
| 404 | `PAYMENT_NOT_FOUND` | Payment does not exist |

**Idempotency:** Yes (verifying an already-verified payment is a no-op).

### 26.3 Get Payment Status
- **Method:** `GET`
- **Path:** `/api/v1/payments/{payment_id}`
- **Auth:** Bearer token required
- **Authorization:** `SHOPKEEPER` role, must own payment

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "id": 1,
    "subscription_id": 1,
    "provider": "RAZORPAY",
    "transaction_id": "pay_abc123",
    "amount": 499.00,
    "currency": "INR",
    "status": "SUCCESS",
    "payment_method": "UPI",
    "paid_at": "2026-08-19T10:00:00Z"
  }
}
```

### 26.4 List Payments
- **Method:** `GET`
- **Path:** `/api/v1/payments`
- **Auth:** Bearer token required
- **Authorization:** `SHOPKEEPER` role

**Query Parameters:**
| Param | Type | Required | Validation |
|---|---|---|---|
| `page` | int | No | Default 1 |
| `limit` | int | No | Default 20, max 100 |
| `filter[status]` | string | No | `PENDING`, `SUCCESS`, `FAILED`, `REFUNDED` |

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "items": [
      {
        "id": 1,
        "subscription_id": 1,
        "amount": 499.00,
        "currency": "INR",
        "status": "SUCCESS",
        "payment_method": "UPI",
        "paid_at": "2026-08-19T10:00:00Z"
      }
    ],
    "pagination": { }
  }
}
```

---

## 27. Complaint APIs (Customer)

### 27.1 Create Complaint
- **Method:** `POST`
- **Path:** `/api/v1/complaints`
- **Auth:** Bearer token required
- **Authorization:** Any authenticated user

**Request Body:**
```json
{
  "complaint_type": "WRONG_PRICE",
  "subject": "Price mismatch",
  "description": "Product was priced higher than displayed",
  "entity_type": "SHOP",
  "entity_id": 1
}
```

| Field | Type | Required | Validation |
|---|---|---|---|
| `complaint_type` | string | Yes | `WRONG_PRICE`, `FAKE_PRODUCT`, `SHOP_ISSUE`, `OTHER` |
| `subject` | string | Yes | 1–255 chars |
| `description` | string | Yes | 1–5000 chars |
| `entity_type` | string | No | `SHOP`, `PRODUCT`, `OFFER` |
| `entity_id` | int | No | Positive integer |

**Response (201):**
```json
{
  "success": true,
  "message": "Complaint submitted",
  "data": {
    "id": 1,
    "complaint_type": "WRONG_PRICE",
    "subject": "Price mismatch",
    "status": "OPEN",
    "priority": "MEDIUM",
    "created_at": "2026-08-19T10:00:00Z"
  }
}
```

**Idempotency:** No.

### 27.2 List My Complaints
- **Method:** `GET`
- **Path:** `/api/v1/complaints`
- **Auth:** Bearer token required
- **Authorization:** Any authenticated user (self only)

**Query Parameters:**
| Param | Type | Required | Validation |
|---|---|---|---|
| `page` | int | No | Default 1 |
| `limit` | int | No | Default 20, max 100 |
| `filter[status]` | string | No | `OPEN`, `IN_PROGRESS`, `RESOLVED`, `CLOSED`, `REJECTED` |

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "items": [
      {
        "id": 1,
        "complaint_type": "WRONG_PRICE",
        "subject": "Price mismatch",
        "description": "Product was priced higher than displayed",
        "status": "OPEN",
        "priority": "MEDIUM",
        "resolution_notes": null,
        "created_at": "2026-08-19T10:00:00Z"
      }
    ],
    "pagination": { }
  }
}
```

### 27.3 Get Complaint Detail
- **Method:** `GET`
- **Path:** `/api/v1/complaints/{complaint_id}`
- **Auth:** Bearer token required
- **Authorization:** Any authenticated user (self only)

**Error Cases:**
| Status | Code | Condition |
|---|---|---|
| 404 | `COMPLAINT_NOT_FOUND` | Complaint not found |
| 403 | `FORBIDDEN` | User does not own this complaint |

---

## 28. Customer Address APIs

### 28.1 List Addresses
- **Method:** `GET`
- **Path:** `/api/v1/addresses`
- **Auth:** Bearer token required
- **Authorization:** Any authenticated user (self only)

**Response (200):**
```json
{
  "success": true,
  "message": "Success",
  "data": {
    "items": [
      {
        "id": 1,
        "label": "Home",
        "address_line1": "123 Main Street",
        "address_line2": "Apt 4B",
        "city": "Patna",
        "state": "Bihar",
        "pincode": "800001",
        "country": "India",
        "latitude": 25.5941,
        "longitude": 85.1376,
        "is_default": true
      }
    ],
    "pagination": { }
  }
}
```

### 28.2 Create Address
- **Method:** `POST`
- **Path:** `/api/v1/addresses`
- **Auth:** Bearer token required
- **Authorization:** Any authenticated user (self only)

**Request Body:**
```json
{
  "label": "Home",
  "address_line1": "123 Main Street",
  "address_line2": "Apt 4B",
  "city": "Patna",
  "state": "Bihar",
  "pincode": "800001",
  "country": "India",
  "latitude": 25.5941,
  "longitude": 85.1376,
  "is_default": true
}
```

| Field | Type | Required | Validation |
|---|---|---|---|
| `label` | string | No | Max 50 chars |
| `address_line1` | string | Yes | 1–255 chars |
| `address_line2` | string | No | Max 255 chars |
| `city` | string | Yes | 1–100 chars |
| `state` | string | Yes | 1–100 chars |
| `pincode` | string | Yes | 6–10 chars |
| `country` | string | No | Default `India` |
| `latitude` | float | No | -90 to 90 |
| `longitude` | float | No | -180 to 180 |
| `is_default` | boolean | No | Default false |

**Response (201):** Created address object.

**Idempotency:** No.

### 28.3 Update Address
- **Method:** `PUT`
- **Path:** `/api/v1/addresses/{address_id}`
- **Auth:** Bearer token required
- **Authorization:** Any authenticated user (self only)

**Idempotency:** Yes.

### 28.4 Delete Address
- **Method:** `DELETE`
- **Path:** `/api/v1/addresses/{address_id}`
- **Auth:** Bearer token required
- **Authorization:** Any authenticated user (self only)

**Idempotency:** Yes.

### 28.5 Set Default Address
- **Method:** `PUT`
- **Path:** `/api/v1/addresses/{address_id}/default`
- **Auth:** Bearer token required
- **Authorization:** Any authenticated user (self only)

**Idempotency:** Yes.

---

## 29. API Documentation Requirements

### 29.1 OpenAPI/Swagger
- All endpoints MUST be documented in OpenAPI 3.0 format.
- FastAPI auto-generates `/docs` and `/redoc`.
- Every endpoint MUST have:
  - Summary
  - Description
  - Request/response schemas
  - Error responses
  - Authentication requirements

### 29.2 Documentation Standards
- All field names use `snake_case`.
- All timestamps use ISO 8601 format with timezone (`2026-08-19T10:00:00Z`).
- All monetary values are floats in the smallest currency unit (INR paise not used; use decimal).
- All IDs are integers unless specified otherwise.

### 29.3 Changelog
- All API changes MUST be documented in a changelog.
- Breaking changes require a new major version.

---

## 30. Frontend Screen → API Mapping

### 30.1 Customer App Screens

| Screen | API Endpoint(s) | Auth |
|---|---|---|
| Splash Screen | `GET /health` | None |
| Onboarding/Login | `POST /auth/send-otp`, `POST /auth/verify-otp` | None |
| Home Screen | `GET /home/feed` | None |
| Search Screen | `GET /search/suggestions` | None |
| Search Results | `GET /search/products` | None |
| Product Detail | `GET /products/id/{product_id}`, `GET /products/{product_id}/compare` | None |
| Product Price Comparison | `GET /products/{product_id}/compare` | None |
| Shop Detail | `GET /shops/{shop_id}` | None |
| Shop Products | `GET /shops/{shop_id}/products` | None |
| Saved Products | `GET /saved-products`, `POST /saved-products/{product_id}`, `DELETE /saved-products/{product_id}` | Bearer |
| Saved Shops | `GET /saved-shops`, `POST /saved-shops/{shop_id}`, `DELETE /saved-shops/{shop_id}` | Bearer |
| Notifications | `GET /notifications`, `PUT /notifications/{id}/read`, `PUT /notifications/read-all` | Bearer |
| Profile | `GET /profile`, `PUT /profile` | Bearer |
| Settings | `GET /notifications/preferences`, `PUT /notifications/preferences` | Bearer |
| Addresses | `GET /addresses`, `POST /addresses`, `PUT /addresses/{id}`, `DELETE /addresses/{id}` | Bearer |
| Search History | `GET /search/history`, `DELETE /search/history`, `DELETE /search/history/{id}` | Bearer |
| Nearby Shops | `GET /shops/nearby`, `GET /locations/nearby` | None |
| Barcode Scan | `GET /products/{barcode}` | None |
| Complaint Form | `POST /complaints` | Bearer |
| My Complaints | `GET /complaints` | Bearer |
| Directions | `GET /shops/{shop_id}` (for coordinates) | None |

### 30.2 Shopkeeper App Operations

| Operation | API Endpoint(s) | Auth |
|---|---|---|
| Login | `POST /auth/send-otp`, `POST /auth/verify-otp` | None |
| Register Shop | `POST /shopkeeper/shops` | Bearer + SHOPKEEPER |
| My Shops | `GET /shopkeeper/shops` | Bearer + SHOPKEEPER |
| Shop Detail | `GET /shopkeeper/shops/{shop_id}` | Bearer + SHOPKEEPER |
| Update Shop | `PUT /shopkeeper/shops/{shop_id}` | Bearer + SHOPKEEPER |
| Submit Verification | `POST /shopkeeper/shops/{shop_id}/verification` | Bearer + SHOPKEEPER |
| Verification Status | `GET /shopkeeper/shops/{shop_id}/verification` | Bearer + SHOPKEEPER |
| Inventory List | `GET /shopkeeper/shops/{shop_id}/inventory` | Bearer + SHOPKEEPER |
| Add Product | `POST /shopkeeper/shops/{shop_id}/inventory` | Bearer + SHOPKEEPER |
| Update Inventory | `PUT /shopkeeper/shops/{shop_id}/inventory/{id}` | Bearer + SHOPKEEPER |
| Update Stock | `PATCH /shopkeeper/shops/{shop_id}/inventory/{id}/stock` | Bearer + SHOPKEEPER |
| Update Price | `PATCH /shopkeeper/shops/{shop_id}/inventory/{id}/price` | Bearer + SHOPKEEPER |
| Remove Product | `DELETE /shopkeeper/shops/{shop_id}/inventory/{id}` | Bearer + SHOPKEEPER |
| Barcode Scan | `POST /shopkeeper/barcode/scan` | Bearer + SHOPKEEPER |
| Scan History | `GET /shopkeeper/barcode/history` | Bearer + SHOPKEEPER |
| Excel Import | `POST /shopkeeper/shops/{shop_id}/inventory/import` | Bearer + SHOPKEEPER |
| Import Status | `GET /shopkeeper/inventory/imports/{import_id}` | Bearer + SHOPKEEPER |
| POS Integration | `POST /shopkeeper/shops/{shop_id}/pos-integrations` | Bearer + SHOPKEEPER |
| POS List | `GET /shopkeeper/shops/{shop_id}/pos-integrations` | Bearer + SHOPKEEPER |
| POS Sync | `POST /shopkeeper/shops/{shop_id}/pos-integrations/{id}/sync` | Bearer + SHOPKEEPER |
| Sync Status | `GET /shopkeeper/pos-sync-jobs/{job_id}` | Bearer + SHOPKEEPER |
| Sync Jobs | `GET /shopkeeper/shops/{shop_id}/pos-sync-jobs` | Bearer + SHOPKEEPER |
| Subscription | `GET /shopkeeper/subscription` | Bearer + SHOPKEEPER |
| Plans | `GET /shopkeeper/subscription/plans` | Bearer + SHOPKEEPER |
| Subscribe | `POST /shopkeeper/subscription/subscribe` | Bearer + SHOPKEEPER |
| Cancel Subscription | `POST /shopkeeper/subscription/cancel` | Bearer + SHOPKEEPER |
| Create Payment | `POST /payments/create-intent` | Bearer + SHOPKEEPER |
| Verify Payment | `POST /payments/verify` | Bearer + SHOPKEEPER |
| Payment Status | `GET /payments/{payment_id}` | Bearer + SHOPKEEPER |
| Payment History | `GET /payments` | Bearer + SHOPKEEPER |

### 30.3 Admin Panel Operations

| Operation | API Endpoint(s) | Auth |
|---|---|---|
| Login | `POST /auth/send-otp`, `POST /auth/verify-otp` | None |
| Dashboard | `GET /admin/analytics/dashboard` | Bearer + ADMIN |
| Shop List | `GET /admin/shops` | Bearer + ADMIN |
| Shop Detail | `GET /admin/shops/{shop_id}` | Bearer + ADMIN |
| Approve Shop | `POST /admin/shops/{shop_id}/approve` | Bearer + ADMIN |
| Reject Shop | `POST /admin/shops/{shop_id}/reject` | Bearer + ADMIN |
| Suspend Shop | `POST /admin/shops/{shop_id}/suspend` | Bearer + ADMIN |
| Reactivate Shop | `POST /admin/shops/{shop_id}/reactivate` | Bearer + ADMIN |
| Verifications | `GET /admin/verifications` | Bearer + ADMIN |
| Review Verification | `POST /admin/verifications/{id}/review` | Bearer + ADMIN |
| Product Approvals | `GET /admin/product-approvals` | Bearer + ADMIN |
| Review Product | `POST /admin/product-approvals/{id}/review` | Bearer + ADMIN |
| User List | `GET /admin/users` | Bearer + ADMIN |
| User Detail | `GET /admin/users/{user_id}` | Bearer + ADMIN |
| Suspend User | `POST /admin/users/{user_id}/suspend` | Bearer + ADMIN |
| Ban User | `POST /admin/users/{user_id}/ban` | Bearer + SUPER_ADMIN |
| Reactivate User | `POST /admin/users/{user_id}/reactivate` | Bearer + ADMIN |
| Subscriptions | `GET /admin/subscriptions` | Bearer + ADMIN |
| Plans | `GET /admin/subscription-plans` | Bearer + ADMIN |
| Create Plan | `POST /admin/subscription-plans` | Bearer + SUPER_ADMIN |
| Update Plan | `PUT /admin/subscription-plans/{plan_id}` | Bearer + SUPER_ADMIN |
| Cancel Subscription | `POST /admin/subscriptions/{id}/cancel` | Bearer + ADMIN |
| Complaints | `GET /admin/complaints` | Bearer + ADMIN |
| Complaint Detail | `GET /admin/complaints/{complaint_id}` | Bearer + ADMIN |
| Update Complaint | `PATCH /admin/complaints/{complaint_id}` | Bearer + ADMIN |
| Product Analytics | `GET /admin/analytics/products` | Bearer + ADMIN |
| Shop Analytics | `GET /admin/analytics/shops` | Bearer + ADMIN |
| Search Analytics | `GET /admin/analytics/search` | Bearer + ADMIN |
| Generate Report | `POST /admin/reports` | Bearer + ADMIN |
| Report Status | `GET /admin/reports/{report_id}` | Bearer + ADMIN |
| Report List | `GET /admin/reports` | Bearer + ADMIN |

---

## 31. Idempotency Requirements Summary

| Endpoint | Idempotent | Notes |
|---|---|---|
| `POST /auth/send-otp` | No | Generates new OTP each call |
| `POST /auth/verify-otp` | No | Consumes OTP |
| `POST /auth/refresh` | No | Rotates tokens |
| `POST /auth/logout` | Yes | |
| `GET *` | Yes | All GET requests are idempotent |
| `PUT *` | Yes | All PUT requests are idempotent |
| `DELETE *` | Yes | All DELETE requests are idempotent |
| `POST /saved-products/{id}` | Yes | Re-saving is a no-op |
| `POST /saved-shops/{id}` | Yes | Re-saving is a no-op |
| `POST /shopkeeper/shops` | No | Creates new shop |
| `POST /shopkeeper/shops/{id}/verification` | No | Creates new verification |
| `POST /shopkeeper/shops/{id}/inventory` | No | Creates new inventory item |
| `PATCH .../stock` | No | Records movement |
| `POST /shopkeeper/barcode/scan` | No | Records scan event |
| `POST .../inventory/import` | No | Creates import job |
| `POST .../pos-integrations` | No | Creates integration |
| `POST .../sync` | No | Creates sync job |
| `POST /payments/create-intent` | No | Creates payment |
| `POST /payments/verify` | Yes | Re-verification is a no-op |
| `POST /admin/shops/{id}/approve` | Yes | |
| `POST /admin/shops/{id}/reject` | Yes | |
| `POST /admin/shops/{id}/suspend` | Yes | |
| `POST /admin/users/{id}/suspend` | Yes | |
| `POST /admin/users/{id}/ban` | Yes | |
| `POST /admin/users/{id}/reactivate` | Yes | |
| `POST /admin/subscriptions/{id}/cancel` | Yes | |
| `POST /admin/reports` | No | Creates report job |
| `POST /complaints` | No | Creates complaint |
| `POST /addresses` | No | Creates address |

---

## 32. Ownership Rules

| Resource | Owner | Access Rule |
|---|---|---|
| User profile | User | Only the user can read/update/delete their own profile |
| Saved products | User | Only the user can read/manage their saved products |
| Saved shops | User | Only the user can read/manage their saved shops |
| Notifications | User | Only the user can read/manage their notifications |
| Search history | User | Only the user can read/clear their search history |
| Addresses | User | Only the user can read/manage their addresses |
| Complaints | User | Only the complainant can read their complaints |
| Shop | Shop owner/manager | Only owners/managers can manage the shop |
| Shop inventory | Shop owner/manager | Only owners/managers can manage inventory |
| Shop verification | Shop owner/manager | Only owners/managers can submit/check verification |
| POS integration | Shop owner/manager | Only owners/managers can manage POS |
| Subscription | Shop owner/manager | Only owners/managers can manage subscription |
| Payments | Shop owner/manager | Only owners/managers can view their payments |
| Admin resources | Admin | Only admins can access admin endpoints |

---

## 33. Validation Test Checklist

- [x] All request schemas defined with field validation
- [x] All response schemas defined
- [x] All error cases documented with status codes
- [x] Pagination structure standardized
- [x] Filtering and sorting documented
- [x] Authentication requirements defined for every endpoint
- [x] Authorization requirements defined for every endpoint
- [x] Idempotency requirements defined
- [x] Rate-limit expectations defined
- [x] Ownership rules defined
- [x] API versioning strategy defined
- [x] Backwards compatibility rules defined
- [x] API documentation requirements defined
- [x] Every Customer App screen mapped to required API
- [x] Every Shopkeeper App operation mapped to required API
- [x] Every Admin operation mapped to required API
- [x] Standard error structure defined
- [x] Standard pagination structure defined
- [x] Standard success response structure defined

---

## 34. Verification: Feature → API Coverage

| Feature | API Contract Defined | Status |
|---|---|---|
| Authentication (OTP, refresh, logout) | §6 | ✅ |
| Customer profile | §7 | ✅ |
| Location (nearby, manual search) | §8 | ✅ |
| Categories | §9 | ✅ |
| Brands | §10 | ✅ |
| Products (barcode, detail, compare) | §11 | ✅ |
| Product variants | §12 | ✅ |
| Shops (nearby, detail, products) | §13 | ✅ |
| Shop products | §14 | ✅ |
| Inventory (product, shop) | §15 | ✅ |
| Pricing (price history) | §16 | ✅ |
| Offers | §17 | ✅ |
| Search (products, suggestions, history, popular) | §18 | ✅ |
| Nearby shops | §19 | ✅ |
| Saved items (products, shops) | §20 | ✅ |
| Notifications (list, read, preferences, device) | §21 | ✅ |
| Home feed | §22 | ✅ |
| Shop registration | §23.1 | ✅ |
| Shop verification | §23.2 | ✅ |
| Product inventory (shopkeeper) | §23.3 | ✅ |
| Barcode (shopkeeper) | §23.4 | ✅ |
| Excel import | §23.5 | ✅ |
| POS integration | §23.6 | ✅ |
| Admin shop management | §24.1 | ✅ |
| Admin verification | §24.2 | ✅ |
| Admin product approval | §24.3 | ✅ |
| Admin user management | §24.4 | ✅ |
| Admin subscription | §24.5 | ✅ |
| Admin complaints | §24.6 | ✅ |
| Admin analytics | §24.7 | ✅ |
| Admin reports | §24.8 | ✅ |
| Subscription (shopkeeper) | §25 | ✅ |
| Payments | §26 | ✅ |
| Complaints (customer) | §27 | ✅ |
| Customer addresses | §28 | ✅ |

**All major frontend features have a defined backend contract. No screen depends on an undefined API.**