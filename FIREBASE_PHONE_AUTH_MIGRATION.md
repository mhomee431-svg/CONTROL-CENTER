# Firebase Phone Authentication — Migration Summary

## Status: ✅ COMPLETE

Fast2SMS has been **removed** from the shopkeeper login/registration OTP flow and
replaced with **Firebase Phone Authentication**.

---

## What Changed

### Architecture (Before → After)

```
BEFORE (Fast2SMS):
  Flutter → Backend → Fast2SMS API → SMS to phone
  Backend generates OTP, stores hash, Fast2SMS delivers it.

AFTER (Firebase Phone Auth):
  Flutter → Firebase Auth (Google) → SMS to phone
  Flutter verifies OTP with Firebase → gets ID token → Backend verifies token
```

### Why Firebase?

| Fast2SMS | Firebase Phone Auth |
|----------|-------------------|
| ₹ per SMS | Free (generous quota) |
| DLT registration needed in India | No DLT needed |
| API key in .env | No SMS key needed |
| Backend sends SMS | Google sends SMS |
| OTP stored in backend | OTP never leaves device |

---

## Files Changed

### Backend

| File | Change |
|------|--------|
| `app/core/config.py` | Added `FIREBASE_CREDENTIALS_FILE` / `FIREBASE_CREDENTIALS_JSON` |
| `app/services/firebase_verification.py` | **NEW** — Verifies Firebase ID token, extracts phone |
| `app/api/routes/shopkeeper_auth.py` | `send-otp` is now a no-op; `register` and `verify-otp` use Firebase token |
| `app/schemas/shopkeeper.py` | `otp` field replaced with `firebase_id_token` |
| `.env` / `.env.example` | Fast2SMS removed, Firebase credentials added |
| `tests/test_shopkeeper_app.py` | Updated to mock `verify_firebase_id_token` |

### Flutter (ShopkeeperApp)

| File | Change |
|------|--------|
| `pubspec.yaml` | Added `firebase_core` + `firebase_auth` |
| `lib/main.dart` | Firebase initialization (skipped in mock mode) |
| `lib/core/network/api_providers.dart` | Added `phoneAuthServiceProvider` |
| `lib/features/auth/data/phone_auth_service.dart` | **NEW** — Firebase Phone Auth wrapper + `FakePhoneAuthService` |
| `lib/features/auth/data/auth_repository.dart` | `registerWithFirebase` / `loginWithFirebase` (no more `sendOtp`) |
| `lib/features/auth/data/mock_auth_repository.dart` | Updated to match new interface |
| `lib/features/auth/presentation/controllers/auth_controller.dart` | `sendOtp` uses Firebase; `submitOtp` verifies then calls backend |
| `lib/features/auth/presentation/screens/login_screen.dart` | Phone sanitization |
| `lib/features/auth/presentation/screens/register_screen.dart` | Phone sanitization |
| `test/auth_flow_test.dart` | Updated for Firebase flow |
| `test/register_navigation_test.dart` | Updated for Firebase flow |
| `test/fakes.dart` | `FakePhoneAuthService` used in tests |

---

## New API Contract

### Register

```json
POST /api/v1/shopkeeper/auth/register
{
  "firebase_id_token": "<firebase-id-token>",
  "phone_number": "+919999999999",
  "name": "Ramesh Kirana",
  "password": "Password123"
}
```

### Login (OTP)

```json
POST /api/v1/shopkeeper/auth/verify-otp
{
  "firebase_id_token": "<firebase-id-token>"
}
```

### Send OTP (No-op)

```json
POST /api/v1/shopkeeper/auth/send-otp
{ "phone_number": "+919999999999" }
→ { "message": "OTP delivery is handled by Firebase Phone Auth on the client" }
```

---

## Setup Instructions

### 1. Firebase Console

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project (or create one)
3. **Authentication** → **Sign-in method** → Enable **Phone**
4. Add your app's SHA-256 fingerprint (Android) / enable Apple Sign-in (iOS)
5. Download the **service account JSON**:
   - Project Settings → Service Accounts → Generate New Private Key
6. Save it as `Backend/hyperlocal--discovery-firebase-adminsdk-fbsvc-3e2c39a88e.json`
   (or update `FIREBASE_CREDENTIALS_FILE` in `.env`)

### 2. Flutter Firebase Setup

```bash
cd ShopkeeperApp
flutter pub get

# Add Firebase configuration files:
# - Android: android/app/google-services.json (from Firebase Console)
# - iOS: ios/Runner/GoogleService-Info.plist (from Firebase Console)

# OR use FlutterFire CLI:
dart pub global activate flutterfire_cli
flutterfire configure
```

### 3. Enable Phone Auth in Firebase Console

- Firebase Console → Authentication → Sign-in method → Phone → **Enable**
- Add test phone numbers for development (optional, bypasses SMS)

### 4. Run

```bash
# Backend
cd Backend
python -m uvicorn app.main:app --reload

# Flutter
cd ShopkeeperApp
flutter run
```

---

## Test Results

| Suite | Result |
|-------|--------|
| Backend — `test_shopkeeper_auth.py` | ✅ 13 passed |
| Backend — `test_shopkeeper_app.py` | ✅ 47 passed |
| Backend — shop management + inventory | ✅ 82 passed |
| **Backend total** | ✅ **142 passed** |
| Flutter — `flutter analyze` | ✅ **No issues found** |
| Flutter — `flutter test` | ✅ **15 passed** |

---

## Environment Variables

### `.env`

```env
# Firebase Phone Authentication (replaces Fast2SMS)
FIREBASE_CREDENTIALS_FILE=hyperlocal--discovery-firebase-adminsdk-fbsvc-3e2c39a88e.json
# FIREBASE_CREDENTIALS_JSON=  # alternative: raw JSON string
```

### Legacy (Customer Auth)

The **customer** OTP flow (`app/api/routes/auth.py`) still uses Fast2SMS and is
unchanged. Only the **shopkeeper** flow uses Firebase.

---

## Mock Mode (Development / CI)

Set `kUseMockAuth = true` in `auth_repository.dart` to bypass Firebase entirely:

```dart
const bool kUseMockAuth = true;  // No Firebase needed
```

The `FakePhoneAuthService` returns a fixed token, and the backend tests mock
`verify_firebase_id_token` to return the expected phone number.

---

**Migration Date:** 2026-09-05
**Status:** ✅ Complete — Fast2SMS removed, Firebase Phone Auth active