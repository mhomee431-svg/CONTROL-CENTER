# Customer App — Google Sign-In (Firebase + FastAPI)

Status: **Android fully wired** (native Credential Manager → Firebase credential →
FastAPI session exchange). **iOS code path implemented but not provisioned**:
`ios/Runner/GoogleService-Info.plist` is absent, so `Firebase.initializeApp()`
cannot start on iOS yet (see §3). Web uses the Firebase JS SDK popup and
requires the web app to be registered in Firebase.

---

## 1. End-to-end flow

```
Flutter (customer_app)
  ├─ GoogleAuthService.signInWithGoogle()
  │    ├─ Android: MethodChannel com.hyperlocal.app/google_auth
  │    │    → Credential Manager → Google ID token
  │    │    → FirebaseAuth.signInWithCredential → Firebase ID token
  │    ├─ iOS: FirebaseAuth.signInWithProvider(GoogleAuthProvider())
  │    └─ Web: FirebaseAuth.signInWithPopup(GoogleAuthProvider())
  │
  └─ ApiAuthRepository.signInWithGoogle()
       → POST /api/v1/auth/google-login { firebase_id_token, device_* }
            │
Backend  ───┴─ verify_firebase_id_token_claims()      (firebase_admin)
              ├─ require provider == "google.com"
              ├─ require email_verified == true
              ├─ UID-first lookup → google_id → single verified email
              ├─ reject ambiguous / cross-role links (409 / 403)
              └─ issue JWT access + refresh tokens
```

The customer app never trusts client-supplied identity: the backend derives
`firebase_uid`, `google_id`, `email`, `name`, and `picture` from the verified
token.

### Backend contract — `POST /api/v1/auth/google-login`

Request (`CustomerGoogleAuthRequest`):

| Field | Type | Notes |
| --- | --- | --- |
| `firebase_id_token` | string | required, min 20 chars |
| `device_id` / `device_name` / `device_type` / `platform` / `app_version` | string? | optional session metadata |

Success `data`: `{access_token, refresh_token, session_id, expires_in, user, is_new_account}`.

| Error code | HTTP | Meaning |
| --- | --- | --- |
| `GOOGLE_PROVIDER_REQUIRED` | 403 | Token is not from the `google.com` provider |
| `GOOGLE_EMAIL_REQUIRED` | 403 | Google account has no email |
| `GOOGLE_EMAIL_NOT_VERIFIED` | 403 | Google did not mark the email verified |
| `GOOGLE_IDENTITY_MISSING` | 403 | Token has no Firebase UID |
| `ACCOUNT_LINK_CONFLICT` | 409 | Email/UID/subject points at multiple accounts |
| `ACCOUNT_ROLE_MISMATCH` | 403 | Matched account is not a customer |
| `ACCOUNT_NOT_ACTIVE` | 403 | Suspended / banned / inactive |
| `FIREBASE_VERIFICATION_FAILED` | 401 | Invalid or expired Firebase token |

Identity rules (deliberately conservative):

1. `firebase_uid` is the durable account key and is looked up first.
2. `google_id` (from `firebase.identities["google.com"]`) is a compatibility
   link, stored separately and never overwritten with the Firebase UID.
3. A verified email links to an existing account **only** when exactly one
   customer owns it and no UID / Google-subject conflict exists.
4. Ambiguous or cross-role matches are rejected — never auto-merged.

---

## 2. Android (works today)

Already present in the repo:

* `android/app/google-services.json` registers `com.hyperlocal.app`
  (mobilesdk app id `1:356092661742:android:dd589bd7bd86ecf54788ff`).
* `android/app/build.gradle.kts` applies `com.google.gms.google-services` and
  now adds:
  * `androidx.credentials:credentials:1.3.0`
  * `androidx.credentials:credentials-play-services-auth:1.3.0`
  * `com.google.android.libraries.identity.googleid:googleid:1.1.1`
* `MainActivity.kt` hosts the MethodChannel `com.hyperlocal.app/google_auth`
  (`signInWithGoogle`, `signOut`, `getCurrentUser`) and exchanges the Google ID
  token for a Firebase credential.
* `SERVER_CLIENT_ID` is the Google **web** OAuth client (`client_type: 3`) from
  `google-services.json`:
  `356092661742-hcvah5tufmgv5eas4ao4ijqk0vope50o.apps.googleusercontent.com`.
  Credential Manager requires the server (web) client ID, not the Android one.

No Google Cloud / Firebase console change is needed beyond the existing
project, provided the Google sign-in provider is enabled in Firebase
Authentication → Sign-in method.


## 3. iOS (code path ready, provisioning pending)

`FirebaseGoogleAuthService` routes iOS to
`FirebaseAuth.signInWithProvider(GoogleAuthProvider())`, which uses
`ASWebAuthenticationSession`. To make it functional:

1. Register an iOS app for bundle id `com.hyperlocal.app` in Firebase.
2. Add `ios/Runner/GoogleService-Info.plist` to the Runner target.
3. Add the reversed iOS OAuth client ID as a `CFBundleURLTypes` scheme in
   `ios/Runner/Info.plist`.
4. Optionally set `iosClientId` / `iosBundleId` when initialising Firebase.

Until step 2 exists, `Firebase.initializeApp()` cannot succeed on iOS, so
Google Sign-In (and phone OTP) remain Android/web-only. This is a
configuration blocker, not a code blocker.

## 4. Mock / offline mode

When `API_BASE_URL` is not configured (local dev, widget tests), the provider
selects `FakeGoogleAuthService` and `MockAuthRepository`, so the Google button,
the auth gate sheet, and `AuthController.signInWithGoogle()` are fully
exercisable without Firebase.

## 5. Guest auth gates

`lib/features/auth/presentation/widgets/auth_gate_sheet.dart` exposes
`requireAuthentication(context, ref, actionLabel: ...)`. It returns `true`
immediately for signed-in customers; otherwise it opens a bottom sheet with
**Continue with Google** (plus a phone-OTP fallback). The underlying screen —
and therefore the customer's return destination — is preserved; the original
action runs right after a successful sign-in.

Applied to:

| Action | File |
| --- | --- |
| Call shop (header button) | `shop_details/presentation/screens/shop_details_screen.dart` |
| Contact rows (phone / secondary phone / email) | same |
| Directions (shop → directions route) | same |
| Open external navigation | `directions/presentation/screens/directions_screen.dart` |

Rating submission is **not gated** because the customer app has no reviews
feature yet (no `features/reviews` module). Add the same
`requireAuthentication(...)` call when it is built.

## 6. Verification

```bash
cd apps/customer_app
dart run build_runner build --delete-conflicting-outputs   # regenerate mocks
flutter analyze
flutter test test/features/auth
```

Backend:

```bash
cd backend
python -m pytest tests/test_customer_google_auth.py -q
```
