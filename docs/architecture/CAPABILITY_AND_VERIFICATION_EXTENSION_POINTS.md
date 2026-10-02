# Capability & Verification — Extension Points

Two product rules shape this codebase, and this file is the map for both:

1. **Future subscription support.** Plan features may come later. Paid-feature
   logic must not be hardcoded across the app; there is exactly one
   capability/entitlement layer. **Payments are not implemented** and must not
   be until explicitly requested.
2. **Future verification.** Business identity, GST/Udyam, bank verification,
   category documents and admin review may come later. They are **not built**;
   only their extension points exist.

Nothing described under "Future" is implemented today. This file records *where
it plugs in* so that landing it is a small, reviewable change rather than a
rewrite.

---

## 1. The one capability layer (shipped)

Paid behaviour is resolved on the server and read, never re-derived, by the
client.

```
  Subscription + Plan rows  (data, operator-tunable via features_json)
        │
        ▼
  entitlements.py ── resolve_shop_entitlements()   grandfathered | live | terminal
        │
        ├── enforce_feature(key)   → 403 ENTITLEMENT_DENIED / SUBSCRIPTION_EXPIRED
        ├── enforce_limit(key)     → 403 PLAN_LIMIT_REACHED
        └── derive_shop_capabilities()  → the four canX display flags
                  │
                  ▼
          capabilities_payload()  →  shop detail · dashboard · /capabilities
                  │
                  ▼
  Flutter: ShopCapabilities → capabilitiesControllerProvider → CapabilityGate
```

| Concern | Single owner |
|---|---|
| Plan names, entitlements, resolution | `backend/app/services/subscription/entitlements.py` |
| Publishing flags to a payload | `shopkeeper_service.capabilities_payload` |
| Raising an entitlement refusal | `entitlements.enforce_feature` / `enforce_limit` |
| Parsing the flags | `ShopCapabilities` in `features/shops/domain/shop_models.dart` |
| Holding them | `capabilitiesControllerProvider` |
| Gating a surface | `core/ui/capability_gate.dart` |

**Three rules that keep it one layer:**

- *A flag is one entitlement, never a plan name.* `canUsePos ⇐ pos_support`.
  Operators rename and retune plans in the DB without a code change.
- *The backend stays authoritative.* Hiding a tile is a display hint; the real
  request still 403s, and the app surfaces the server's upgrade copy via
  `ApiException.isEntitlementDenied`.
- *Fail open, never closed.* An absent flags block, or a resolution error,
  yields the permissive set. The worst case is a visible feature that 403s —
  never a hidden one that works.

### Guarded, not just documented

Two architecture tests fail the build if this decays:

- `backend/tests/test_capability_layer_boundary.py` — no `plan.name == …` or
  `PLAN_TEMPLATES[…]` outside the subscription package; the `canX` keys have
  exactly one producer; no payment provider configured in settings.
- `apps/shopkeeper_app/test/capability_layer_boundary_test.dart` — no feature
  screen branches on a plan name or the subscription status; no
  `isPro`/`isPremium`-style helper; the `canX` fields are declared in one file.

Each was verified to fail on a deliberately-introduced violation, not just to
pass on a clean tree.

### Adding a new paid capability later

1. Add the entitlement to `ENTITLEMENT_CATALOG` (and to the plan templates).
2. Add one line to `derive_shop_capabilities` returning the new `canX` flag.
3. Add the matching `final bool canX` to `ShopCapabilities.fromJson`.
4. Gate the surface with `CapabilityGate`.

No screen logic, no plan-name checks. The boundary tests keep steps 1–4 honest.

---

## 2. Future: payments (not implemented)

Deliberately absent. `TestFuturePaymentWorkIsNotWiredIn` asserts that no
payment provider is configured in `app/core/config.py`.

The subscription *data model* and entitlement *resolution* already exist
(`app/models/subscription.py`, `app/services/subscription/`); what is missing
is a payment execution path (gateway, webhooks, invoice state). When that is
requested, it belongs behind a provider seam mirroring the verification
providers in §3, configured by settings like `IDENTITY_PROVIDER` — never
called directly from a route.

---

## 3. Future: verification (extension points exist, feature not built)

The backend seams are **already in place and mounted**; the Flutter client has
no surface for them. That asymmetry is deliberate — the client work is the part
that should wait for a settled contract.

### Backend (ready)

State machine — `app/models/merchant_onboarding.py`:

```
DRAFT → PHONE_VERIFIED → IDENTITY_PENDING → IDENTITY_VERIFIED
      → BANK_PENDING → BANK_VERIFIED
      → CATEGORY_DOCUMENTS_PENDING → CATEGORY_DOCUMENTS_VERIFIED
      → PENDING_ADMIN_REVIEW → VERIFIED
                              ↘ REJECTED · RESUBMISSION_REQUIRED · SUSPENDED
```

`VALID_ONBOARDING_TRANSITIONS` is the single authority on legal moves;
`_validate_transition` in `merchant_onboarding_service.py` enforces it.

Provider seams — three interchangeable ABCs, each with a sandbox
implementation and a settings-keyed factory that falls back to sandbox:

| Seam | File | Factory | Provider key |
|---|---|---|---|
| Identity (GSTIN/Udyam) | `app/services/identity_provider.py` | `get_identity_provider()` | `IDENTITY_PROVIDER` |
| Bank | `app/services/bank_provider.py` | `get_bank_provider()` | `BANK_PROVIDER` |
| Category documents | `app/services/category_provider.py` | `get_category_provider()` | `CATEGORY_PROVIDER` |

All three return a normalised result carrying `status` / `provider` /
`reference_id` / `failure_reason` / `failure_code`, so swapping ClearTax or
Razorpay in for the sandbox changes no caller.

> No free government API exists for GSTIN/Udyam. Until a real provider is
> onboarded, results route to `PENDING_ADMIN_REVIEW` — which is why the
> sandbox refuses to run in production.

HTTP surface (mounted in `app/main.py`):

| Method | Path |
|---|---|
| `POST` | `/api/v1/shopkeeper/businesses/{business_id}/onboarding` |
| `GET` | `/api/v1/shopkeeper/businesses/{business_id}/onboarding-status` |
| `GET` | `/api/v1/shopkeeper/businesses/{business_id}/verification/requirements` |
| `POST` | `…/verification/phone` · `…/identity` · `…/bank` · `…/category` · `…/retry` |
| `GET` | `/api/v1/admin/merchant-onboarding/{onboarding_id}` |
| `POST` | `/api/v1/admin/merchant-onboarding/{onboarding_id}/review` |

An onboarding record is created automatically when a shop is registered
(`shopkeeper_service.get_or_create_onboarding`).

### Flutter (the seam to add — not written yet)

`ShopCapabilities` is the pattern to copy. When the verification UI is
scheduled:

1. Add an `OnboardingStatus` model parsed from `GET …/onboarding-status` — a
   **separate** model from `ShopCapabilities`. Compliance and monetization are
   different axes; merging them would make "this shop is verified" and "this
   shop may use POS" the same question.
2. Add a `verificationControllerProvider` beside
   `capabilitiesControllerProvider`, mirroring `adopt()` / `reset()`, with
   `reset()` called in `AuthController.logout()` — per-account, like the
   capability flags.
3. Render each step from the server's `status`; never derive a step locally.

### The rule that matters when both land

If verification ever *gates* a feature — e.g. "payouts require
`BANK_VERIFIED`" — that gate is a **capability**, not a verification check in
a screen. Add it to `derive_shop_capabilities` alongside the entitlement and
let the existing layer carry it. Otherwise the two systems drift, and the
boundary tests above are what stop it.

