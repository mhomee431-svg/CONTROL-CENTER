# AUDIT REPORT — Tiered Merchant Onboarding & Legal Verification System

**Date:** 2026-09-07
**Scope:** Phase 0 Audit — Complete Backend Repository Inspection
**Status:** AUDIT COMPLETE — Ready for Architecture Design

---

## 1. EXISTING RELEVANT MODULES

### 1.1 Application Structure
```
Backend/
├── app/
│   ├── main.py                    # FastAPI app, lifespan, middleware, router registration
│   ├── core/
│   │   ├── config.py              # Settings (pydantic-settings), env profiles
│   │   ├── dependencies.py        # Auth deps, RBAC deps, shop access deps
│   │   ├── security.py            # JWT, password hashing, token validation
│   │   ├── exceptions.py          # Typed AppError hierarchy
│   │   ├── responses.py           # success_response / error_response helpers
│   │   ├── logging.py             # Structured logging setup
│   │   ├── rate_limit.py          # SlowAPI rate limiter
│   │   ├── middleware.py           # RequestID, SecurityHeaders
│   │   ├── redis.py               # Redis client options
│   │   ├── cache.py               # Redis cache abstraction
│   │   ├── admin_permissions.py   # Admin RBAC permission catalog
│   │   ├── shopkeeper_permissions.py  # Shopkeeper permission catalog
│   │   ├── resource_ownership.py  # Shop ownership verification
│   │   ├── startup_checks.py      # Production security gate
│   │   └── observability/         # Metrics, alerting, deployment tracking
│   ├── api/routes/
│   │   ├── auth.py                # Customer auth (Fast2SMS OTP + password)
│   │   ├── shopkeeper_auth.py     # Shopkeeper auth (Firebase OTP + password)
│   │   ├── shopkeeper_portal.py   # Shopkeeper business routes
│   │   ├── admin.py               # Admin platform routes
│   │   ├── shops.py               # Shop CRUD routes
│   │   ├── restaurant.py          # Restaurant discovery routes
│   │   ├── transport.py           # Transport booking routes
│   │   ├── categories.py          # Product categories
│   │   ├── catalog.py             # Product catalog
│   │   ├── inventory.py           # Inventory management
│   │   ├── search.py              # Search & discovery
│   │   ├── locations.py           # Location routes
│   │   ├── media.py               # S3/media upload routes
│   │   ├── pos_integration.py     # POS integration routes
│   │   ├── interactions.py        # Customer interactions/leads
│   │   ├── notifications.py       # Push notifications
│   │   ├── reviews.py             # Reviews
│   │   ├── analytics_system.py    # Analytics & audit
│   │   ├── shopkeeper_subscription.py  # Subscriptions
│   │   ├── shopkeeper_analytics.py     # Shopkeeper analytics
│   │   ├── shopkeeper_extra.py    # Shopkeeper docs/hours/holidays
│   │   ├── customer.py            # Customer experience
│   │   └── google_auth.py         # Google OAuth
│   ├── models/                    # SQLAlchemy ORM models
│   ├── schemas/                   # Pydantic request/response schemas
│   ├── services/                  # Business logic layer
│   ├── database/
│   │   ├── session.py             # Base, engines, session factories, PostGIS bootstrap
│   │   └── base.py                # (not present — base is in session.py)
│   └── search/                    # Search indexing
├── alembic/
│   ├── versions/                  # 18 migrations (0001–0018)
│   ├── env.py
│   └── script.py.mako
├── tests/                         # Comprehensive test suite
└── docs/                          # API contracts, architecture docs
```

### 1.2 Key Existing Services
| Service | Path | Purpose |
|---------|------|----------|
| `auth_service.py` | `app/services/` | Token issuance, session management, refresh rotation |
| `shopkeeper_service.py` | `app/services/` | Shop registration, product/inventory management, shop access resolution |
| `shop_service.py` | `app/services/` | Core shop CRUD |
| `admin_service.py` | `app/services/` | Admin platform: shop verification, product approval, complaints, audit |
| `otp_service.py` | `app/services/` | OTP generation, verification, expiry, retry limits |
| `otp_store.py` | `app/services/` | OTP storage abstraction (memory/Redis) |
| `fast2sms_otp_service.py` | `app/services/` | Fast2SMS delivery adapter |
| `firebase_verification.py` | `app/services/` | Firebase ID token verification |
| `restaurant_service.py` | `app/services/` | Restaurant discovery CRUD |
| `transport_service.py` | `app/services/` | Transport booking logic |
| `geo_service.py` | `app/services/` | Haversine distance, geospatial helpers |
| `media_service.py` | `app/services/` | S3/media upload, signed URLs |
| `pos_sync_service.py` | `app/services/` | POS integration, credential encryption |
| `sms_service.py` | `app/services/` | SMS provider abstraction (mock/Msg91/AWS SNS) |
| `audit_service.py` | `app/services/` | Tamper-evident audit log hashing |

---

## 2. EXISTING TABLES (Relevant to Merchant Onboarding)

### 2.1 User & Auth Tables
| Table | Model | Key Fields |
|-------|-------|------------|
| `users` | `User` | id, phone_number, google_id, name, email, password_hash, role_id, status |
| `roles` | `Role` | id, name, description |
| `permissions` | `Permission` | id, name, resource, action |
| `role_permissions` | association | role_id, permission_id |
| `user_roles` | association | user_id, role_id, assigned_at |
| `auth_sessions` | `AuthSession` | session_id, user_id, is_active, is_revoked, device info |
| `token_blacklists` | `TokenBlacklist` | jti, expires_at |
| `password_resets` | `PasswordReset` | user_id, token, expires_at |
| `otps` | `Otp` | phone_number, otp_hash, salt, expires_at, attempts |

### 2.2 Shop / Business Tables
| Table | Model | Key Fields |
|-------|-------|------------|
| `shops` | `Shop` | id, name, slug, description, phone, category, status, gstin, fssai_license, latitude, longitude, rating, is_verified, created_by |
| `shop_owners` | `ShopOwner` | id, shop_id, user_id, is_active, ownership_type |
| `shop_managers` | `ShopManager` | id, shop_id, user_id, is_active, permissions (JSON) |
| `shop_addresses` | `ShopAddress` | id, shop_id, address_line1, city, state, pincode, latitude, longitude, geolocation (PostGIS), is_verified |
| `shop_hours` | `ShopHour` | id, shop_id, day_of_week, open_time, close_time |
| `shop_holidays` | `ShopHoliday` | id, shop_id, holiday_date, is_recurring_yearly |
| `shop_documents` | `ShopDocument` | id, shop_id, document_type, document_url, document_number, expires_at, is_verified, verified_by, rejection_reason |
| `shop_verifications` | `ShopVerification` | id, shop_id, status, submitted_by, reviewed_by, review_notes, submitted_at, reviewed_at, verified_at, expires_at |

### 2.3 Domain-Specific Tables
| Table | Model | Key Fields |
|-------|-------|------------|
| `restaurants` | `Restaurant` | id, shop_id, cuisine_types, licence_fssai, avg_cost_for_two, veg_only |
| `restaurant_menu_categories` | `RestaurantMenuCategory` | id, restaurant_id, name, sort_order |
| `restaurant_menu_items` | `RestaurantMenuItem` | id, restaurant_id, menu_category_id, name, price, veg |
| `transport_providers` | `TransportProvider` | id, user_id, shop_id, company_name, license_number, verification_status |
| `vehicles` | `Vehicle` | id, provider_id, vehicle_type, registration_number, capacity_passengers |
| `vehicle_documents` | `VehicleDocument` | id, vehicle_id, document_type, document_url, document_number, valid_until, is_verified |
| `transport_services` | `TransportService` | id, provider_id, service_type, base_fare |
| `transport_bookings` | `TransportBooking` | id, provider_id, vehicle_id, booking_ref, pickup_address, destination, trip_date, agreed_amount |

### 2.4 Admin & Governance Tables
| Table | Model | Key Fields |
|-------|-------|------------|
| `admin_actions` | `AdminAction` | id, admin_user_id, action_type, target_type, target_id, action_data, ip_address |
| `admin_notes` | `AdminNote` | id, admin_user_id, entity_type, entity_id, note, is_private |
| `product_approvals` | `ProductApproval` | id, product_master_id, shop_id, status, reviewed_by, review_notes |
| `audit_logs` | `AuditLog` | id, user_id, action, entity_type, entity_id, old_values, new_values, ip_address, request_id, is_success, reason, prev_record_hash, record_hash |
| `reports` | `Report` | id, report_type, report_name, status |
| `complaints` | `Complaint` | id, complainant_user_id, complaint_type, subject, status, priority |

---

## 3. EXISTING APIs (Relevant to Merchant Onboarding)

### 3.1 Shopkeeper Auth APIs
| Method | Path | Purpose |
|--------|------|----------|
| POST | `/api/v1/shopkeeper/auth/send-otp` | Firebase phone OTP (client-side delivery) |
| POST | `/api/v1/shopkeeper/auth/register` | Register with Firebase token + password |
| POST | `/api/v1/shopkeeper/auth/login` | Password-based login |
| POST | `/api/v1/shopkeeper/auth/otp-login` | Firebase OTP login |
| POST | `/api/v1/shopkeeper/auth/firebase-login` | Combined login-or-register |
| POST | `/api/v1/shopkeeper/auth/refresh` | Token rotation |
| POST | `/api/v1/shopkeeper/auth/logout` | Session revocation |
| GET | `/api/v1/shopkeeper/auth/me` | Current user + authorized shops |

### 3.2 Shopkeeper Business APIs
| Method | Path | Purpose |
|--------|------|----------|
| GET | `/api/v1/shopkeeper/shops` | List authorized shops |
| POST | `/api/v1/shopkeeper/shops` | Register new shop (becomes owner) |
| GET | `/api/v1/shopkeeper/shops/{shop_id}` | Shop detail |
| PATCH | `/api/v1/shopkeeper/shops/{shop_id}` | Update shop profile |
| POST | `/api/v1/shopkeeper/shops/{shop_id}/location` | Update shop location |
| GET | `/api/v1/shopkeeper/shops/{shop_id}/products` | List shop products |
| POST | `/api/v1/shopkeeper/shops/{shop_id}/products` | Add product |
| ... | ... | (full product/inventory/offer CRUD) |

### 3.3 Admin APIs (Shop Verification)
| Method | Path | Purpose |
|--------|------|----------|
| GET | `/api/v1/admin/shops` | List shops with filters |
| GET | `/api/v1/admin/shops/{shop_id}` | Shop detail |
| POST | `/api/v1/admin/shops/{shop_id}/verify` | Verify/reject/suspend/reactivate shop |
| GET | `/api/v1/admin/shops/{shop_id}/documents` | List shop documents |
| GET | `/api/v1/admin/audit-logs` | Audit trail |
| GET | `/api/v1/admin/actions` | Admin action history |

### 3.4 Restaurant APIs
| Method | Path | Purpose |
|--------|------|----------|
| GET | `/api/v1/restaurants/nearby` | Discover nearby restaurants |
| GET | `/api/v1/restaurants/{id}` | Restaurant detail + menu |
| POST | `/api/v1/restaurants` | Create restaurant profile |
| PATCH | `/api/v1/restaurants/{id}` | Update restaurant |

### 3.5 Transport APIs
| Method | Path | Purpose |
|--------|------|----------|
| GET | `/api/v1/transport/providers` | List transport providers |
| POST | `/api/v1/transport/providers` | Register as provider |
| GET | `/api/v1/transport/vehicles` | List vehicles |
| POST | `/api/v1/transport/bookings` | Create booking |

---

## 4. EXISTING AUTHENTICATION

### 4.1 Mechanism
- **JWT Bearer tokens** (HS256) with access/refresh token pair
- **Session-aware**: Each token carries `session_id`; `AuthSession` table tracks active sessions
- **Token blacklisting**: `TokenBlacklist` table for revoked tokens
- **Refresh token rotation**: New refresh token issued on each use; reuse detection revokes session
- **Account status check**: Suspended/Banned/INACTIVE users are rejected

### 4.2 Dependencies
- `get_current_user(credentials, db)` — resolves user from JWT, validates session + account status
- `get_current_user_with_session(credentials, db)` — returns (user, claims) tuple
- `require_admin_permission(resource, action)` — admin RBAC gate
- `require_shop_permission(shop_id, resource, action)` — shop-scoped permission gate

### 4.3 Roles
- `customer` — default for customer app signups
- `shopkeeper` — for shopkeeper app users (auto-assigned on shop ownership)
- `admin` — full platform access
- Additional admin-family roles with granular permissions

---

## 5. EXISTING SHOPKEEPER/BUSINESS FLOW

### 5.1 Current Flow
```
Shopkeeper Registration (Firebase OTP + password)
    ↓
Login → JWT issued
    ↓
POST /shopkeeper/shops → register_shop_for_shopkeeper()
    ↓
    Creates Shop (status=REGISTERED)
    Creates ShopOwner (is_active=True)
    Creates ShopAddress (with lat/lng + PostGIS)
    ↓
Shopkeeper manages products, inventory, offers
    ↓
Admin reviews → POST /admin/shops/{id}/verify (VERIFY/REJECT/SUSPEND)
```

### 5.2 Shop Status State Machine (Current)
```
REGISTERED → DOCUMENTS_SUBMITTED → PENDING_VERIFICATION → VERIFIED
                                                    → REJECTED
                                                    → SUSPENDED
                                                    → ACTIVE / CLOSED
```

### 5.3 Shop Access Control
- `resolve_shop_access(db, user, shop_id)` → `ShopAccess` dataclass
- Admins: global bypass
- Owners: full catalog (dashboard, shop, product, inventory, offer)
- Managers: reduced catalog ∩ granted permission subset
- Non-authorized: `ForbiddenError` (403)

---

## 6. EXISTING LOCATION FLOW

### 6.1 Implementation
- `ShopAddress` model: `latitude`, `longitude`, `geolocation` (PostGIS `Geography("POINT", srid=4326)`)
- Location enums: `LocationSource` (GPS/MANUAL/ADDRESS), `LocationType` (SHOP_ENTRANCE/BUILDING_CENTER), `LocationStatus` (CAPTURED/CONFIRMED/CORRECTED/STALE), `LocationIntegrityStatus` (NORMAL/SUSPICIOUS/UNKNOWN)
- `geo_service.py`: Haversine distance calculation
- PostGIS bootstrap: `enable_postgis()` runs `CREATE EXTENSION IF NOT EXISTS "postgis"` on startup

### 6.2 Location Capture
- Shopkeeper provides GPS coordinates during shop registration
- Stored in `shop_addresses` with `geolocation` PostGIS point
- `is_verified` flag on address

---

## 7. EXISTING ADMIN REVIEW FLOW

### 7.1 Current Implementation
- `POST /api/v1/admin/shops/{shop_id}/verify` with `ShopVerificationAction` schema
- Decisions: `VERIFY | REJECT | SUSPEND | REACTIVATE`
- Requires `admin` role + `("shop", "verify")` permission
- Records `AuditLog` + `AdminAction` for every decision
- Updates `Shop.status` and creates `ShopVerification` record

### 7.2 Admin Permissions
- Granular RBAC: `require_admin_permission(resource, action)`
- Resources: dashboard, customer, shop, product, inventory, offer, subscription, audit_log, admin_action, admin_note, etc.

---

## 8. EXISTING VERIFICATION CODE

### 8.1 OTP Verification
- **Customer app**: Fast2SMS (`fast2sms_otp_service.py`) — generates 6-digit OTP, stores hashed in `otps` table, delivers via Fast2SMS (mock/live)
- **Shopkeeper app**: Firebase Phone Auth — client-side OTP delivery, backend verifies Firebase ID token (`firebase_verification.py`)
- **OTP service** (`otp_service.py`): Shared OTP logic — expiry, max attempts, resend cooldown, hashed storage, constant-time comparison
- **OTP store** (`otp_store.py`): Pluggable backends — `InMemoryOTPStore` (dev/test), `RedisOTPStore` (production)

### 8.2 Shop Verification
- `ShopVerification` model: tracks status (PENDING/SUBMITTED/UNDER_REVIEW/VERIFIED/REJECTED/EXPIRED)
- `ShopDocument` model: stores document_type (GST, LICENSE, PAN, FSSAI, OTHER), document_url, document_number, is_verified
- Admin manually reviews documents and approves/rejects

### 8.3 What Exists for Category-Specific Verification
- `shops.gstin` — GSTIN field (VARCHAR(50)) — stored but NOT verified programmatically
- `shops.fssai_license` — FSSAI field (VARCHAR(50)) — stored but NOT verified programmatically
- `restaurants.licence_fssai` — FSSAI for restaurants — stored but NOT verified
- `transport_providers.license_number` — transport license — stored but NOT verified
- `transport_providers.verification_status` — simple string field
- `vehicles.registration_number` — vehicle registration
- `vehicle_documents` — insurance/registration/permit/driving_license documents

---

## 9. REUSABLE COMPONENTS

### 9.1 Directly Reusable
| Component | Reuse For |
|-----------|-----------|
| `User` model + auth system | Merchant user accounts |
| `Role`/`Permission` + RBAC | Merchant role management |
| `Shop` model (core fields) | Business entity base |
| `ShopOwner`/`ShopManager` | Business memberships |
| `ShopAddress` + PostGIS | Business location |
| `ShopDocument` | Document storage |
| `ShopVerification` | Verification tracking |
| `AdminAction`/`AuditLog` | Admin review audit trail |
| `otp_service.py` + `otp_store.py` | Phone OTP verification |
| `firebase_verification.py` | Shopkeeper phone verification |
| `admin_service.record_audit_log()` | Audit trail for all verification actions |
| `admin_service.record_admin_action()` | Admin action tracking |
| `media_service.py` | Secure document uploads (S3 signed URLs) |
| `geo_service.py` | Distance/validation helpers |
| `BaseOTPStore` abstraction | OTP provider pattern (template for other providers) |
| `POSProvider` abstraction pattern | Template for verification provider abstractions |
| `PaymentProvider` abstraction pattern | Template for bank verification providers |
| Provider registry pattern (`pos_integration`) | Verification provider registry |

### 9.2 Patterns to Reuse
- **Provider abstraction**: `BaseOTPStore` → `InMemoryOTPStore`/`RedisOTPStore` — same pattern for identity/bank/category providers
- **Mock provider pattern**: `MockPOSProvider` — deterministic mock for testing
- **Admin RBAC**: `require_admin_permission(resource, action)` — extend for merchant verification permissions
- **Shop access resolution**: `resolve_shop_access()` — extend for business-level access control
- **Audit logging**: `record_audit_log()` + `record_admin_action()` — use for all verification events
- **Typed exceptions**: `AppError`, `ForbiddenError`, `ValidationError`, `NotFoundError`, `ConflictError`
- **Response helpers**: `success_response()` / `error_response()`

---

## 10. DUPLICATE COMPONENTS

### 10.1 Potential Duplicates to Avoid
| Existing | New System | Resolution |
|----------|------------|------------|
| `shops.gstin` | Merchant identity verification GSTIN | **Reuse** — extend with verification status fields |
| `shops.fssai_license` | Restaurant FSSAI verification | **Reuse** — extend with verification status |
| `restaurants.licence_fssai` | Restaurant FSSAI verification | **Consolidate** — single FSSAI verification flow |
| `shop_documents` | Verification document storage | **Reuse** — extend document_type enum |
| `shop_verifications` | Merchant onboarding verification | **Extend** — add new states for tiered onboarding |
| `transport_providers.verification_status` | Transport verification | **Integrate** — route through common verification layer |
| `ShopStatus` enum | Merchant onboarding status | **Separate** — onboarding status ≠ operational status |
| `VerificationStatus` enum | Verification step status | **Extend** — add new states |

### 10.2 Conceptual Overlap
- `ShopStatus` (REGISTERED/VERIFIED/ACTIVE...) is an **operational** status
- The new system needs a separate **onboarding/verification** status
- These must be kept separate per the spec

---

## 11. MISSING COMPONENTS

### 11.1 New Models Needed
| Model | Purpose |
|-------|----------|
| `MerchantCategory` | Centralized category configuration (11 categories) |
| `MerchantVerificationRequirement` | Category-specific requirement configuration |
| `MerchantOnboarding` | Onboarding state machine per business |
| `BusinessIdentityVerification` | GSTIN/UDYAM verification records |
| `BankAccountVerification` | Bank penny-drop verification records |
| `CategoryDocumentVerification` | Pharmacy/Restaurant/Transport document verification |
| `VerificationAttempt` | Audit trail of each verification attempt |
| `VerificationProviderLog` | Provider interaction log (references, not secrets) |

### 11.2 New Services Needed
| Service | Purpose |
|---------|----------|
| `MerchantOnboardingService` | Orchestrate full onboarding flow |
| `VerificationOrchestrator` | Coordinate verification steps |
| `CategoryRequirementResolver` | Resolve requirements per category |
| `BusinessIdentityVerificationService` | GSTIN/UDYAM provider abstraction + verification |
| `BankVerificationService` | Bank penny-drop provider abstraction |
| `CategoryVerificationService` | Pharmacy/FSSAI/Transport document verification |
| `AdminReviewService` | Admin review workflow for verification |

### 11.3 New Provider Abstractions Needed
| Provider | Purpose |
|----------|----------|
| `IdentityVerificationProvider` | GSTIN/UDYAM verification (interface) |
| `BankAccountVerificationProvider` | Bank penny-drop (interface) |
| `CategoryVerificationProvider` | Category document verification (interface) |
| Sandbox implementations | Deterministic test responses |

### 11.4 New APIs Needed
| API | Purpose |
|-----|----------|
| `POST /shopkeeper/businesses` | Start onboarding |
| `GET /shopkeeper/businesses` | List merchant businesses |
| `GET /shopkeeper/businesses/{id}` | Business detail + onboarding status |
| `POST /shopkeeper/businesses/{id}/verification/start` | Start verification |
| `POST /shopkeeper/businesses/{id}/verification/retry` | Retry failed step |
| `GET /shopkeeper/businesses/{id}/verification/requirements` | Required checks |
| `GET /shopkeeper/businesses/{id}/onboarding-status` | Current status + next action |
| `POST /shopkeeper/businesses/{id}/verification/identity` | Submit GSTIN/UDYAM |
| `POST /shopkeeper/businesses/{id}/verification/bank` | Submit bank details |
| `POST /shopkeeper/businesses/{id}/verification/category` | Submit category documents |
| `GET /admin/merchant-onboarding` | List pending onboardings |
| `POST /admin/merchant-onboarding/{id}/review` | Admin approve/reject |

### 11.5 New Schemas Needed
- `MerchantOnboardingRequest` (business_name, category_code, phone, email, address, location, gstin, udyam, bank, category_details)
- `VerificationRequirementResponse`
- `OnboardingStatusResponse`
- `IdentityVerificationRequest`
- `BankVerificationRequest`
- `CategoryVerificationRequest`
- `AdminOnboardingReviewRequest`

---

## 12. SECURITY PROBLEMS

### 12.1 Current Security Posture (Strong)
- No hardcoded secrets in source code (verified via search)
- JWT secret loaded from env; production security gate warns on defaults
- OTP hashed with salt (HMAC-SHA256) before storage
- OTP never returned in production response
- Rate limiting on auth endpoints (SlowAPI)
- RBAC with granular permissions
- Shop-scoped access control (IDOR protection)
- Audit logging with tamper-evident hash chaining
- S3 signed URLs for media (private buckets)
- POS credentials encrypted at rest

### 12.2 Security Considerations for New System
| Risk | Mitigation |
|------|------------|
| Bank account number exposure | Encrypt at rest; mask in API responses (show last 4 digits only) |
| GSTIN/UDYAM data | Store only what is needed; do not log full identifiers |
| Document upload security | Reuse existing S3 signed URL pattern; validate content-type, size, scan for malware |
| IDOR on business resources | Extend `resolve_shop_access` pattern for business-level access |
| Provider API keys | Load from env/secrets manager only; never hardcode |
| Verification bypass | Backend-only state machine; never trust frontend status |
| OTP abuse | Existing rate limiting + cooldown + max attempts |
| Sandbox data in production | Environment-based provider selection; production blocks sandbox |

---

## 13. MIGRATION RISKS

### 13.1 Risk Areas
| Risk | Impact | Mitigation |
|------|--------|------------|
| Adding columns to `shops` table | Existing shop data | Use ALTER TABLE ADD COLUMN with defaults; backward-compatible |
| New tables alongside existing | No data migration needed | Create new tables; no existing data to migrate |
| `ShopStatus` vs onboarding status | Conceptual confusion | Keep separate; document clearly |
| `restaurants.licence_fssai` vs new FSSAI verification | Dual storage | New verification record references existing field; do not duplicate |
| `transport_providers.verification_status` vs new system | Status conflict | New system supersedes; migrate existing values |
| Existing admin verification flow | Admin UX | Extend existing flow; do not break current admin APIs |

### 13.2 Safe Migration Strategy
1. Create new tables (no existing data affected)
2. Add new columns to `shops` with NULL defaults (backward-compatible)
3. New APIs are additive (no existing APIs modified)
4. Existing admin verification continues to work
5. Gradual migration: new onboardings use new system; existing shops unaffected

---

## 14. RECOMMENDED FINAL ARCHITECTURE

### 14.1 Architecture Principles
1. **Extend, do not duplicate** — Reuse `Shop`, `ShopOwner`, `ShopAddress`, `ShopDocument`, `ShopVerification`, `AuditLog`
2. **Separate onboarding from operations** — New `MerchantOnboarding` state machine is independent of `ShopStatus`
3. **Provider abstraction** — All external verification behind interfaces (Identity, Bank, Category)
4. **Sandbox-first** — Deterministic mock providers for dev/test; production requires explicit enablement
5. **Admin review fallback** — When no authorized API exists, route to admin review (never scrape, never fabricate)
6. **Audit everything** — Every verification attempt, every admin action, every state transition

### 14.2 Proposed Data Model (New + Existing)
```
[EXISTING] users ──┬──< user_roles >── roles
                   ├──< shop_owners >── shops ──< shop_addresses (PostGIS)
                   ├──< shop_managers >──┘       ├──< shop_documents
                   └──< auth_sessions >           ├──< shop_verifications
                                                  ├──< restaurants
                                                  └──< transport_providers

[NEW] merchant_categories (11 categories config)
[NEW] merchant_verification_requirements (category requirements config)
[NEW] merchant_onboardings (per-business onboarding state)
[NEW] business_identity_verifications (GSTIN/UDYAM records)
[NEW] bank_account_verifications (bank penny-drop records)
[NEW] category_document_verification (pharmacy/restaurant/transport docs)
[NEW] verification_attempts (audit trail of each attempt)
[NEW] verification_provider_logs (provider interaction metadata)
```

### 14.3 Verification State Machine
```
DRAFT → PHONE_VERIFIED → IDENTITY_PENDING → BANK_PENDING
    → CATEGORY_DOCUMENTS_PENDING → PENDING_ADMIN_REVIEW → VERIFIED
                                                        → REJECTED
                                                        → SUSPENDED
```

### 14.4 Provider Architecture
```
IdentityVerificationProvider (interface)
├── SandboxIdentityProvider (deterministic mock)
└── ProductionIdentityProvider (placeholder — requires real API onboarding)

BankAccountVerificationProvider (interface)
├── SandboxBankProvider (deterministic mock)
├── CashfreeBankProvider (adapter — requires official API docs)
└── RazorpayBankProvider (adapter — requires official API docs)

CategoryVerificationProvider (interface)
├── SandboxCategoryProvider (deterministic mock)
├── PharmacyProvider (drug license — admin review fallback)
├── FssaiProvider (FSSAI/FoSCoS — admin review fallback)
└── TransportProvider (VAHAN/Parivahan — admin review fallback)
```

### 14.5 Category Configuration Approach
- `merchant_categories` table: code, name, description, is_active
- `merchant_verification_requirements` table: category_id, requirement_code, requirement_name, is_required, verification_method, requires_admin_review
- This allows adding new categories/requirements without code changes
- Category-specific details stored as JSON in `merchant_onboardings.category_details`

### 14.6 API Design
- New routes under `/api/v1/shopkeeper/businesses/*` for onboarding
- New routes under `/api/v1/admin/merchant-onboarding/*` for admin review
- Existing `/api/v1/shopkeeper/shops/*` and `/api/v1/admin/shops/*` remain untouched
- Consistent response format: `{ business_id, onboarding_status, verification: {...}, next_action }`

---

## 15. COMPLIANCE LIMITATIONS

### 15.1 What Cannot Be Automated (No Authorized API)
| Verification | Current Status | Fallback |
|--------------|----------------|----------|
| GSTIN verification | No official free API; paid services exist (ClearTax, Razorpay) | Sandbox + PENDING_ADMIN_REVIEW |
| UDYAM/MSME verification | No official free API | Sandbox + PENDING_ADMIN_REVIEW |
| Drug license verification | No centralized API | PENDING_ADMIN_REVIEW |
| FSSAI/FoSCoS verification | FoSCoS portal exists but no public API | PENDING_ADMIN_REVIEW |
| VAHAN/Parivahan (vehicle/driver) | No public API | PENDING_ADMIN_REVIEW |
| Bank account verification | Cashfree/Razorpay offer paid APIs | Sandbox + PENDING_ADMIN_REVIEW |

### 15.2 Compliance Rules
- Never scrape government portals
- Never bypass CAPTCHA
- Never fabricate verification results
- Store only legally required data
- Follow Indian privacy/data-protection requirements
- Use language: VERIFIED / PENDING ADMIN REVIEW / REJECTED / UNABLE TO VERIFY

---

## 16. IMPLEMENTATION READINESS

### 16.1 Pre-Implementation Checklist
- [x] Complete repository audit
- [x] Identify reusable components
- [x] Identify duplicates to avoid
- [x] Identify missing components
- [x] Assess security posture
- [x] Assess migration risks
- [x] Design final architecture
- [ ] User approval of architecture
- [ ] Begin Phase 1 implementation

### 16.2 Recommended Implementation Order
1. Database architecture finalization + migrations
2. Category configuration (`merchant_categories`, `merchant_verification_requirements`)
3. Merchant onboarding state machine
4. OTP service integration (reuse existing)
5. Identity verification abstraction (GSTIN/UDYAM)
6. Bank verification abstraction (penny-drop)
7. Category verification abstraction (pharmacy/restaurant/transport)
8. Admin review workflow
9. Secure document handling (reuse existing S3)
10. GPS/PostGIS business location (reuse existing)
11. REST APIs
12. Sandbox providers
13. Tests
14. Full test suite + migration verification

---

## 17. SUMMARY

The existing codebase is a **production-grade FastAPI application** with:
- Solid authentication (JWT + sessions + RBAC)
- Comprehensive admin platform with audit trails
- Well-designed provider abstractions (OTP, POS, payments)
- PostGIS location infrastructure
- Secure media handling (S3 signed URLs)
- Strong security posture (no hardcoded secrets, rate limiting, IDOR protection)

The new Tiered Merchant Onboarding system can **reuse ~70% of existing infrastructure** and needs ~30% new code focused on:
- Category configuration layer
- Verification state machine
- Provider abstractions for identity/bank/category verification
- Admin review workflow for verification
- New APIs (additive, non-breaking)

**No existing functionality will be broken.** All new code is additive.

---

*End of Audit Report*
