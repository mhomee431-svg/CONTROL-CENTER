# Secure Phone OTP Authentication via Fast2SMS (single-use)

The customer auth flow verifies phone numbers through a 6-digit one-time
password delivered by **Fast2SMS** and persisted in the `otps` table as a
**single-use**, 5-minute-expiring record.

## How it works

```
POST /api/v1/auth/send-otp ──► generate 6-digit code
                              ├─► persist Otp(phone, digest, expires_at, is_verified=False)
                              └─► deliver via Fast2SMS (mock prints / live sends SMS)

POST /api/v1/auth/verify-otp ─► match code (constant-time) + not expired + not used
                              ├─► atomically flip is_verified = True  ← single-use
                              └─► issue access + refresh JWTs (+ create user if new)
```

## Configuration

| Env var            | Value            | Meaning                                                        |
|--------------------|------------------|----------------------------------------------------------------|
| `FAST2SMS_API_KEY` | `<api key>`      | Authorization header for `https://www.fast2sms.com/dev/bulkV2` |
| `OTP_MODE`         | `mock` \| `live` | `mock` prints OTP to console (₹0); `live` sends real SMS       |

`OTP_MODE=mock` is the default for development/test. Switch it to `live`
only when you actually want to spend Fast2SMS balance.
`FAST2SMS_API_KEY` is optional in mock mode but **required** in live mode —
a missing key raises `SMS_DELIVERY_FAILED` (HTTP 502) rather than silently
pretending the SMS went out.

## Delivery helper (`app/services/fast2sms.py`)

* `OTP_MODE=mock` → `print("[MOCK OTP] ...")` to the server console.
* `OTP_MODE=live` → POST to Fast2SMS:

  ```http
  POST https://www.fast2sms.com/dev/bulkV2
  authorization: <FAST2SMS_API_KEY>
  Content-Type: application/json

  {
    "route": "otp",
    "variables_values": "<otp_code>",
    "numbers": "<phone_number>"
  }
  ```

  Live-mode failures (network, HTTP ≥ 400, or `{"return": false}` in the
  body) raise `Fast2SMSDeliveryError` and the stored OTP is rolled back.

## Database schema (`otps`)

| Column         | Type            | Notes                                       |
|----------------|-----------------|---------------------------------------------|
| `id`           | Integer (PK)    | indexed                                     |
| `phone_number` | String(20)      | indexed; E.164-ish (`+91...`)               |
| `otp_code`     | String(128)     | `<salt>:<sha256-hmac>` digest — never raw   |
| `expires_at`   | DateTime(tz)    | 5-minute validity window                    |
| `is_verified`  | Boolean         | default `false`; flipped `true` on success  |
| `created_at`   | DateTime(tz)    | from `TimestampMixin`                       |
| `updated_at`   | DateTime(tz)    | from `TimestampMixin`                       |

Migration: `Backend/alembic/versions/0012_fast2sms_otp_records.py`
(`alembic upgrade head`).

## API contract

### `POST /api/v1/auth/send-otp`
Body: `{"phone_number": "+919999999999"}`

* 200 — `{"success": true, "data": {"expires_in": 300, "dev_otp": "123456"}}`
  (`dev_otp` only with `OTP_DEV_MODE=true`).
* 429 — `OTP_COOLDOWN` (resend too fast) / `OTP_RESEND_LIMIT_REACHED`.
* 502 — `SMS_DELIVERY_FAILED` (live mode failure).

### `POST /api/v1/auth/verify-otp`
Body: `{"phone_number": "+919999999999", "otp": "123456", ...device}`

| Result | HTTP | Error code      |
|--------|------|-----------------|
| Success| 200  | — (tokens)      |
| Wrong/none| 400| `INVALID_OTP`   |
| Expired| 400  | `OTP_EXPIRED`   |
| Already used| 400| `OTP_ALREADY_USED` |

On success the matching `otps` row is marked `is_verified = true` **inside
the same request** — a replayed code is rejected with `OTP_ALREADY_USED`.

## Security properties

* Codes come from `secrets` (CSPRNG), 6 numeric digits.
* Raw codes are **never** persisted — only a salted HMAC-SHA256 digest.
* Verification uses `hmac.compare_digest` (constant time).
* The single-use flip is an atomic `UPDATE ... WHERE is_verified = false`,
  so concurrent duplicate redemption is impossible.
* Codes expire after 5 minutes regardless of delivery.
* Cooldown (`OTP_COOLDOWN_SECONDS`) and resend caps
  (`OTP_MAX_RESENDS`) reuse the same settings as the shopkeeper flow.

## Notes

* The shopkeeper app keeps its existing Redis-backed OTP service untouched;
  only the customer flow was moved to the DB-backed single-use model.
* To test for free: leave `OTP_MODE=mock`; the code appears in the server
  console on every `/send-otp`.
* To go live: set `OTP_MODE=live` and export `FAST2SMS_API_KEY` via your
  secret manager.