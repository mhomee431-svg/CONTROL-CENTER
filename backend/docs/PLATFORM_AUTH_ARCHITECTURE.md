# Hyperlocal Platform — Auth & Interactions Architecture

This document describes the complete authentication and customer-interaction
architecture built on the **"Public Browse + Action-Triggered Verification"**
model with cost-optimised SMS (Fast2SMS) and Google OAuth.

## 1. Product / access model

| Activity | Auth required? |
|---|---|
| Browse shops, products, listings, search | ❌ No (100% public) |
| View contact / Call Now |  JWT (phone-OTP **or** Google login) |
| Send message / chat to a shop |  JWT |
| Give rating & review (with a review message) |  JWT |
| Shopkeeper registers/adds a shop |  Compulsory phone-OTP verification |
| Shopkeeper views inbound leads |  JWT + own/manage scope |

Browsing never requires login. The moment a customer performs a restricted
action (`POST /api/v1/interactions/action`), the JWT gate fires: an anonymous
caller receives **401** and must verify via `send-otp → verify-otp` or
Google OAuth first.

## 2. Verification methods

### 2a. Phone OTP (Fast2SMS)

- `POST /api/v1/auth/send-otp` — generates a CSPRNG 6-digit code, persists a
  5-minute-expiring record in `otps` with `is_verified=False`, and delivers it:
  - `OTP_MODE=mock` → printed to the server console (₹0).
  - `OTP_MODE=live` → POST to
    `https://www.fast2sms.com/dev/bulkV2` with header
    `authorization: <FAST2SMS_API_KEY>` and body
    `{"route":"otp","variables_values":"<otp>","numbers":"<phone>"}`.
- `POST /api/v1/auth/verify-otp` — matches the stored code (salted
  HMAC-SHA256 digest, constant-time compare), enforces expiry and
  `is_verified=False`, then **immediately flips `is_verified=True`**
  (single-use), creates/loads the user, and issues JWT session tokens.

Security properties: raw codes are never stored (only
`salt:hmac-sha256` digests); the single-use flip is an atomic
`UPDATE ... WHERE is_verified = false`; resend cooldown + caps match the
shopkeeper flow settings.

### 2b. Google OAuth (social login)

- `POST /api/auth/google` — returns the Google consent URL plus a short-lived,
  **signed** CSRF `state` token.
- `GET /api/auth/google/callback` — exchanges `?code` for tokens, verifies
  the Google **ID token** against Google's published JWKS (signature + `aud`
  + `iss` + `exp` + `email_verified`), upserts the user by `google_id`, and
  issues JWT session tokens.

The callback route is mounted at the exact path parsed from
`GOOGLE_CALLBACK_URL` (default
`http://localhost:5000/api/auth/google/callback`), so it matches the
redirect URI registered in the Google Cloud Console.

## 3. Roles

- **customer** (default): public browsing + verified interactions.
- **shopkeeper**: assigned at OTP-verified shop registration
  (`/api/v1/shopkeeper/auth/register` requires the shop-owner's phone OTP);
  gets the shopkeeper dashboard.

## 4. Database schema (new/changed)

### users (changed)
- `phone_number` now nullable (Google-only accounts), unique, indexed.
- `google_id` added — unique, indexed (Google `sub`).

### otps (new, from Fast2SMS OTP milestone)
| column | type | notes |
|---|---|---|
| id | Integer PK | indexed |
| phone_number | String(20) | indexed |
| otp_code | String(128) | `salt:hmac-sha256` digest (never raw) |
| expires_at | DateTime(tz) | 5-minute validity |
| is_verified | Boolean | default false; flipped true on use |

### user_interactions (new — immutable leads)
| column | type | notes |
|---|---|---|
| id | Integer PK | indexed |
| user_id | FK users.id | cascade delete, indexed |
| shop_id | FK shops.id | cascade delete, indexed |
| action_type | enum(`call_view`,`message`,`rating`) | indexed |
| message_content | Text | inquiry / review text |
| rating | Integer | 1–5 CHECK constraint |
| created_at / updated_at | DateTime(tz) | TimestampMixin |

**Immutability:** an interaction is *create-only*. There are no update or
delete routes (or service functions) for these records anywhere in the API —
customers cannot edit or delete a rating/review/message once submitted, and
shopkeepers cannot alter them either.

## 5. API reference

### Auth
| Endpoint | Auth | Notes |
|---|---|---|
| `POST /api/v1/auth/send-otp` | — | generates + persists + delivers OTP |
| `POST /api/v1/auth/verify-otp` | — | single-use verify → JWT |
| `POST /api/v1/auth/resend-otp` | — | cooldown/cap enforced |
| `POST /api/auth/google` | — | returns consent URL + state |
| `GET /api/auth/google/callback` | — | code exchange → JWT |

### Interactions (action gate)
| Endpoint | Auth | Notes |
|---|---|---|
| `POST /api/v1/interactions/action` | **JWT (required)** | create-only lead/rating/review |
| `GET /api/v1/interactions/me` | JWT | customer's own interactions |
| `GET /api/v1/interactions/shop/{shop_id}` | — | public, read-only reviews |

### Shopkeeper dashboard
| Endpoint | Auth | Notes |
|---|---|---|
| `POST /api/v1/shopkeeper/auth/register` | compulsory phone-OTP | creates `shopkeeper` account |
| `POST /api/v1/shopkeeper/shops` | JWT + shopkeeper | adds a shop (OTP-verified flow) |
| `GET /api/v1/shopkeeper/leads` | JWT + own/manage scope | verified customer leads |

Leads responses mask customer phone numbers (e.g. `+91********01`) and expose
only the customer's name, action, message and rating.

## 6. Runbook

1. Copy `backend/.env.example` → `backend/.env`.
2. Keep `OTP_MODE=mock` for ₹0 testing (OTP prints in the server console).
   Flip to `OTP_MODE=live` only when you want to spend Fast2SMS balance.
3. Register the OAuth client callback (`GOOGLE_CALLBACK_URL`) in Google Cloud
   Console, then set `GOOGLE_CLIENT_ID`/`GOOGLE_CLIENT_SECRET`.
4. `alembic upgrade head` (runs migrations 0012 otps, 0013 google+leads).
5. `uvicorn app.main:app`.

Production secrets (`FAST2SMS_API_KEY`, `GOOGLE_CLIENT_ID/SECRET`,
`JWT_SECRET_KEY`) must come from the secret manager, never env files.