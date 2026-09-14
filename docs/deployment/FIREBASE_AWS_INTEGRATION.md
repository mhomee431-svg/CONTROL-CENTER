# Firebase Google Auth + AWS Backend — Complete Integration (FINAL)

## Status: ✅ IMPLEMENTED & VERIFIED (all config matches your exact values)

## Verified Firebase Configuration

| Setting | Value | Verified |
|---------|-------|----------|
| Project ID | `hyperlocal--discovery` | ✅ |
| Project Number | `357522455251` | ✅ |
| Android Package | `com.Hyperlocal.app` | ✅ |
| App ID | `1:357522455251:android:626b388e32e3c14ecfb226` | ✅ |
| Service Account | `firebase-adminsdk-fbsvc@hyperlocal--discovery.iam.gserviceaccount.com` | ✅ |
| **Admin SDK JSON** | `backend/hyperlocal--discovery-firebase-adminsdk-fbsvc-ae70d9bfb7.json` | ✅ (exact name, 2403 bytes, private_key_id `ae70d9bfb7...`) |
| **google-services.json** | `apps/shopkeeper_app/android/app/google-services.json` | ✅ |

## Google Only Auth — Current MVP decision

The platform now authenticates Shopkeepers **exclusively via Google Sign-In**
(Credential Manager). Phone-OTP remains only as a future extension surface
(`/send-otp`, `/verify-phone` are intentionally not wired to any UI).

---

## Minimal Google Data Boundary (Phase 19) — AWS

### Purpose

Google exposes a lot of account data. The backend stores ONLY:

| Field | Source claim | Persisted |
|-------|-------------|-----------|
| Firebase UID | `sub` | ✅ (identity link `users.firebase_uid`) |
| Display name | `name` | ✅ (`users.display_name`) |
| Email | `email` | ✅ (`users.email`) |
| Avatar URL | `picture` | ✅ (`users.avatar_url`) |
| Email verified hint | `email_verified` | ❌ (never persisted; read-only) |

No Google access token, refresh token, contacts, drive, locale, hosted-domain
(`hd`) data — nothing else is read, stored, or exposed.

### Enforcement Layer

| File | Role |
|------|------|
| `backend/app/services/google_profile_service.py` | Whitelist `ALLOWED_GOOGLE_CLAIM_KEYS`; `extract_minimal_profile()` rejects any forbidden credential/code claim (e.g. `access_token`, `refresh_token`) |
| `backend/app/api/routes/shopkeeper_auth.py` → `/firebase-login` | Calls `extract_minimal_profile(claims["claims"])` before touching the DB — only `minimal.name / email / picture` are used |
| `backend/app/api/routes/shopkeeper_auth.py` → `GET /api/v1/shopkeeper/auth/google-profile` | Verifies the Firebase token then returns ONLY the minimal fields + `required_scopes` |

### API: GET `/api/v1/shopkeeper/auth/google-profile`

```
Authorization: Bearer <Firebase ID Token>

200 → data: {
  "name": "Home",
  "email": "home91334@gmail.com",
  "picture": "https://…/s96-c",
  "email_verified": true,
  "provider": "google.com",
  "required_scopes": ["openid", "email", "profile"]
}
401 → { "error_code": "FIREBASE_VERIFICATION_FAILED" }
```

- Verified via `verify_firebase_id_token_claims` (cached) in a thread pool.
- `firebase_uid` is included for identity linking but **never** returned to the
  client in profile payloads (minimal exposure).

### Client (Flutter)

- `apps/shopkeeper_app/lib/core/network/api_endpoints.dart` → `googleProfile`
- `apps/shopkeeper_app/lib/features/auth/data/auth_repository.dart` →
  `fetchGoogleProfile()` contract + `ApiAuthRepository` implementation, plus
  fakes in `test/fakes.dart` and `mock_auth_repository.dart`.
- Native `MainActivity.kt` requests **no extra OAuth scopes** — Credential
  Manager default `openid email profile` only.

### AWS Deployment

The boundary is code-only (no new AWS infra): the same Docker image
(`backend/Dockerfile`) + compose stack must be redeployed.

```bash
# On the app EC2 (from /opt/hyperlocal):
./infrastructure/scripts/deploy_backend.sh deploy origin/main
./infrastructure/scripts/deploy_backend.sh verify   # includes /health + /ready

# Confirm the endpoint is live:
curl -s https://api.<your-domain>/api/v1/shopkeeper/auth/google-profile \
  -H "Authorization: Bearer <firebase-id-token>"
```

Firebase service-account credentials flow through the existing AWS Secrets
Manager hydration (`USE_AWS_SECRETS=true`, run in `entrypoint.sh`); the
minimal-data service adds no secret surface.

### Tests

```bash
cd backend
python -m pytest tests/test_google_profile_service.py -v    # 5 passed
python -m pytest tests/test_firebase_auth.py tests/test_google_oauth.py \
  tests/test_identity_access.py -q                          # 68 passed total
```

## The /firebase-login Flow (implemented + tested)

```
Flutter (Firebase Google Sign-In via Credential Manager)
   ├─ native Google account selection → Firebase ID token
   └─ POST /api/v1/shopkeeper/auth/firebase-login  { firebase_id_token, name?, email?, photo_url? }

Backend (FastAPI, on AWS)
   ├─ verify_firebase_id_token_claims(token)   # firebase_admin.auth.verify_id_token (thread-pooled, cached)
   ├─ extract_minimal_profile(claims)          # whitelisted Google fields only
   ├─ uid = claims["sub"] → SELECT user WHERE firebase_uid = uid
   ├─ if none → create_shopkeeper_account(name, email, avatar)  # auto-register, role=SHOPKEEPER
   ├─ if suspended/banned → 403
   └─ issue_tokens(user) → custom JWT access + refresh → response

Response:
   { access_token, refresh_token, token_type, expires_in, user, shops,
     is_new_account: true|false }
```

---

## Gradle / Flutter (all configured)

| File | Config |
|------|--------|
| `android/settings.gradle.kts` | google-services plugin 4.5.0 resolution |
| `android/build.gradle.kts` | `com.google.gms:google-services:4.5.0` classpath |
| `android/app/build.gradle.kts` | google-services plugin + BoM `34.18.0` + firebase-auth; `applicationId = "com.Hyperlocal.app"` |
| `pubspec.yaml` | `firebase_core: ^4.0.0`, `firebase_auth: ^6.0.0` |
| `google-services.json` | exact App ID match ✅ |
| `android/…/MainActivity.kt` | Credential Manager, `setServerClientId`, no extra scopes ✅ |

---

## Final Test Results (ALL GREEN)

| Suite | Result |
|-------|--------|
| Backend — `test_google_profile_service.py` | ✅ **5 passed** |
| Backend — Firebase auth + Google OAuth + identity | ✅ **68 passed** |
| Backend — full shopkeeper suite | ✅ **147 passed** |
| Flutter analyze | ✅ **No issues found** |
| Flutter test | ✅ **15 passed** |

---

## Local Run

```bash
# Backend
cd backend
python -m uvicorn app.main:app --reload

# Flutter (real Firebase Google auth — kUseMockAuth = false)
cd apps/shopkeeper_app
run_on_phone.bat   # auto-detects Wi-Fi IP; NEVER plain `flutter run` on a physical device
```

---

**Status:** ✅ COMPLETE — Google-only auth, minimal-data boundary, AWS-ready.