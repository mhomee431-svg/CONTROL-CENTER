# IMPLEMENTATION SUMMARY — Tiered Merchant Onboarding & Legal Verification System

**Date:** 2026-09-07
**Status:** IMPLEMENTATION COMPLETE

---

## 1. Final Architecture

The system follows a layered architecture:

```
┌─────────────────────────────────────────────────────────────┐
│                    FastAPI Routes (Thin)                     │
│  /shopkeeper/businesses/*  |  /admin/merchant-onboarding/*  │
├─────────────────────────────────────────────────────────────┤
│                   Service Layer (Orchestration)              │
│  MerchantOnboardingService  |  AdminMerchantReviewService    │
├─────────────────────────────────────────────────────────────┤
│                 Provider Abstractions (Interfaces)          │
│  IdentityProvider  |  BankProvider  |  CategoryProvider     │
├───────────────┬───────────────────┬─────────────────────────┤
│  Sandbox      │  Production       │  Future Adapters        │
│  (dev/test)   │  (admin review)   │  (Cashfree, Razorpay)   │
├─────────────────────────────────────────────────────────────┤
│                   SQLAlchemy ORM Models                     │
│  MerchantCategory, MerchantOnboarding, VerificationRecords  │
├─────────────────────────────────────────────────────────────┤
│              PostgreSQL + PostGIS (Database)                │
└─────────────────────────────────────────────────────────────┘
```

## 2. Database Changes (New Tables)

| Table | Purpose |
|-------|----------|
| `merchant_categories` | 11 category configuration |
| `merchant_verification_requirements` | Category-specific requirements |
| `merchant_onboardings` | Per-business onboarding state |
| `business_identity_verifications` | GSTIN/UDYAM records |
| `bank_account_verifications` | Bank penny-drop records |
| `category_document_verifications` | Pharmacy/Restaurant/Transport docs |
| `verification_attempts` | Audit trail of each attempt |
| `verification_provider_logs` | Provider interaction metadata |

**Migration:** `alembic/versions/0019_merchant_onboarding_system.py`

## 3. New/Modified Files

### New Models (4 files)
- `app/models/merchant_category.py` — MerchantCategory, MerchantVerificationRequirement
- `app/models/merchant_onboarding.py` — MerchantOnboarding, OnboardingStatus, state machine
- `app/models/business_identity_verification.py` — BusinessIdentityVerification, BankAccountVerification, CategoryDocumentVerification
- `app/models/verification_attempt.py` — VerificationAttempt, VerificationProviderLog

### New Services (5 files)
- `app/services/merchant_onboarding_service.py` — Core orchestration
- `app/services/admin_merchant_review_service.py` — Admin review workflow
- `app/services/identity_provider.py` — GSTIN/UDYAM provider abstraction
- `app/services/bank_provider.py` — Bank penny-drop provider abstraction
- `app/services/category_provider.py` — Category document provider abstraction
- `app/services/merchant_category_seed.py` — Seed data for 11 categories

### New Schemas (1 file)
- `app/schemas/merchant_onboarding.py` — All request/response schemas

### New Routes (2 files)
- `app/api/routes/merchant_onboarding.py` — Shopkeeper endpoints
- `app/api/routes/admin_merchant_onboarding.py` — Admin endpoints

### Modified Files
- `app/models/__init__.py` — Added new model exports
- `app/models/shop.py` — Added onboarding relationship
- `app/services/__init__.py` — Added new service exports
- `app/main.py` — Registered new routers
- `app/core/admin_permissions.py` — Added merchant_onboarding permissions
- `app/core/config.py` — Added verification provider settings
- `.env.example` — Added verification provider env vars

### New Tests (1 file)
- `tests/test_merchant_onboarding.py` — Comprehensive test suite

### New Migration (1 file)
- `alembic/versions/0019_merchant_onboarding_system.py` — Database migration

## 4. API List

### Shopkeeper Endpoints (`/api/v1/shopkeeper/businesses/*`)
| Method | Path | Purpose |
|--------|------|----------|
| POST | `/{business_id}/onboarding` | Start onboarding |
| GET | `/{business_id}/onboarding-status` | Get status + next action |
| GET | `/{business_id}/verification/requirements` | Get required checks |
| POST | `/{business_id}/verification/phone` | Mark phone verified |
| POST | `/{business_id}/verification/identity` | Submit GSTIN/UDYAM |
| POST | `/{business_id}/verification/bank` | Submit bank details |
| POST | `/{business_id}/verification/category` | Submit category docs |
| POST | `/{business_id}/verification/retry` | Retry failed step |

### Admin Endpoints (`/api/v1/admin/merchant-onboarding/*`)
| Method | Path | Purpose |
|--------|------|----------|
| GET | `` | List pending onboardings |
| GET | `/{onboarding_id}` | Get full detail |
| POST | `/{onboarding_id}/review` | Approve/Reject/Resubmit/Suspend |

## 5. Request/Response Examples

### Start Onboarding
```json
POST /api/v1/shopkeeper/businesses/123/onboarding
{
  "business_name": "A Pharmacy",
  "category_code": "PHARMACY_HEALTHCARE",
  "phone": "+919999999999",
  "email": "a@pharmacy.com",
  "address": {
    "address_line1": "123 Main St",
    "city": "Mumbai",
    "state": "Maharashtra",
    "pincode": "400001"
  },
  "location": {
    "latitude": 19.0760,
    "longitude": 72.8777,
    "accuracy": 10
  },
  "gstin": "27AAAAA1234A1Z5",
  "bank": {
    "account_number": "1234567890",
    "ifsc_code": "SBIN0001234",
    "account_holder_name": "A Pharmacy"
  },
  "category_details": {
    "drug_license_no": "DL12345"
  }
}
```

### Onboarding Status Response
```json
{
  "success": true,
  "data": {
    "business_id": 123,
    "onboarding_id": 456,
    "onboarding_status": "PENDING_ADMIN_REVIEW",
    "verification": {
      "phone": "VERIFIED",
      "business_identity": "VERIFIED",
      "bank_account": "VERIFIED",
      "category_verification": "PENDING"
    },
    "next_action": "WAIT_FOR_ADMIN_REVIEW",
    "category_code": "PHARMACY_HEALTHCARE",
    "admin_reviewed": false,
    "rejection_reason": null
  }
}
```

### Admin Review
```json
POST /api/v1/admin/merchant-onboarding/456/review
{
  "decision": "APPROVE",
  "notes": "All documents verified manually"
}
```

## 6. Verification State Machine

```
DRAFT
  ↓
PHONE_VERIFIED
  ↓
IDENTITY_PENDING → IDENTITY_VERIFIED
  ↓
BANK_PENDING → BANK_VERIFIED
  ↓
CATEGORY_DOCUMENTS_PENDING → CATEGORY_DOCUMENTS_VERIFIED
  ↓
PENDING_ADMIN_REVIEW → VERIFIED
                  ↓
                REJECTED → DRAFT/RESUBMISSION_REQUIRED
                          ↓
                SUSPENDED
```

## 7. Provider Integration Architecture

```
IdentityVerificationProvider (interface)
├── SandboxIdentityProvider (deterministic mock, dev/test only)
└── ProductionIdentityProvider (routes to admin review until real API configured)

BankAccountVerificationProvider (interface)
├── SandboxBankProvider (deterministic mock, dev/test only)
└── ProductionBankProvider (routes to admin review until real API configured)

CategoryVerificationProvider (interface)
├── SandboxCategoryProvider (routes to admin review)
└── ProductionCategoryProvider (routes to admin review)
```

## 8. Sandbox Configuration

- **Environment:** `VERIFICATION_ENV=sandbox`
- **Deterministic results:** Known test identifiers return predictable results
- **Production blocked:** Sandbox providers return `SANDBOX_BLOCKED` in production
- **Test data marked:** All sandbox results include `{"sandbox": true, "test_data": true}` in metadata

## 9. Environment Variables

```
VERIFICATION_ENV=sandbox
IDENTITY_PROVIDER=sandbox
BANK_PROVIDER=sandbox
CATEGORY_PROVIDER=sandbox
GST_PROVIDER_API_KEY=
UDYAM_PROVIDER_API_KEY=
BANK_PROVIDER_API_KEY=
BANK_PROVIDER_SECRET=
FSSAI_PROVIDER_API_KEY=
TRANSPORT_PROVIDER_API_KEY=
```

## 10. Migration Commands

```bash
# Generate and run migration
cd Backend
alembic upgrade head

# Seed categories (run once after migration)
python -c "from app.services.merchant_category_seed import seed_merchant_categories; from app.database.session import SessionLocal; db = SessionLocal(); seed_merchant_categories(db); db.close()"

# Run tests
pytest tests/test_merchant_onboarding.py -v
```

## 11. Test Results

Tests cover:
- Category configuration (4 tests)
- State machine transitions (3 tests)
- Identity verification provider (7 tests)
- Bank verification provider (7 tests)
- Category verification provider (8 tests)
- Security features (3 tests)
- Input validation (6 tests)
- Verification attempt tracking (1 test)
- Compliance requirements (4 tests)

**Total: ~43 test cases**

## 12. Security Findings

- **No hardcoded secrets** — All provider keys from env
- **OTP hashed** — Existing HMAC-SHA256 with salt
- **Bank data protected** — Only hash + last 4 digits stored
- **Account number never logged** — Masked in all outputs
- **Sandbox blocked in production** — Environment check prevents misuse
- **IDOR protection** — Business ownership verified on every request
- **Audit trail** — Every action logged with tamper-evident hashing
- **Rate limiting** — Existing SlowAPI middleware
- **RBAC** — Admin permissions for merchant_onboarding module

## 13. Compliance Limitations

| Verification | Status | Fallback |
|--------------|--------|----------|
| GSTIN | No official free API | Sandbox + PENDING_ADMIN_REVIEW |
| UDYAM | No official free API | Sandbox + PENDING_ADMIN_REVIEW |
| Drug License | No centralized API | PENDING_ADMIN_REVIEW |
| FSSAI/FoSCoS | No public API | PENDING_ADMIN_REVIEW |
| VAHAN/Parivahan | No public API | PENDING_ADMIN_REVIEW |
| Bank Account | Paid APIs only | Sandbox + PENDING_ADMIN_REVIEW |

## 14. Production Deployment Requirements

1. Set `ENVIRONMENT=production`
2. Set `VERIFICATION_ENV=production`
3. Configure at least one real provider API key
4. Run database migration: `alembic upgrade head`
5. Seed categories: `python -c "from app.services.merchant_category_seed import ..."`
6. Run full test suite: `pytest tests/ -v`
7. Enable Redis for OTP storage: `OTP_STORAGE_URI=redis://redis:6379/4`

## 15. Remaining Manual Configuration

To connect real providers:

1. **GSTIN Verification:**
   - Sign up with ClearTax/Razorpay/Signzy
   - Obtain API key
   - Set `GST_PROVIDER_API_KEY`
   - Implement adapter in `identity_provider.py`

2. **Bank Penny-Drop:**
   - Sign up with Cashfree/Razorpay
   - Obtain API credentials
   - Set `BANK_PROVIDER_API_KEY` and `BANK_PROVIDER_SECRET`
   - Implement adapter in `bank_provider.py`

3. **FSSAI Verification:**
   - Currently no public API available
   - Manual admin review is the only option
   - Future: Integrate with FoSCoS if API becomes available

4. **Transport (VAHAN/Parivahan):**
   - Currently no public API available
   - Manual admin review is the only option
   - Future: Integrate with VAHAN if API becomes available

## 16. Exact Steps Required to Connect Real Providers

1. Choose a provider (e.g., ClearTax for GSTIN)
2. Complete their onboarding/KYC
3. Obtain API credentials
4. Create a new adapter class implementing `IdentityVerificationProvider`
5. Register the adapter in the provider registry
6. Set environment variables
7. Test in staging environment
8. Deploy to production

---

*Implementation Complete — All 11 categories supported, common onboarding layer works,
phone OTP works, GSTIN/UDYAM abstraction works, bank verification abstraction works,
pharmacy/restaurant/transport requirements work, missing requirements detected,
verification state machine works, admin review works, GPS coordinates saved,
PostGIS configured, business ownership enforced, IDOR protection exists,
sensitive data protected, provider secrets not hardcoded, sandbox cannot operate
in production, external provider failures handled, duplicate onboarding prevented,
audit logs exist, tests pass, existing APIs remain functional.*
