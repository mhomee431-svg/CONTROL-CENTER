# Firebase Configuration Files

This folder contains reusable Firebase configuration files for all apps in the project.

## Files

| File | Purpose |
|------|---------|
| `google-services.json` | Android Firebase config (google-services plugin) |

## Usage

### Android
Copy to your Android app:
```bash
cp config/firebase/google-services.json apps/<app_name>/android/app/google-services.json
```

### iOS (if needed)
Download `GoogleService-Info.plist` from Firebase Console and place in:
```
apps/<app_name>/ios/Runner/GoogleService-Info.plist
```

## Current OAuth Clients (Android)

| Client ID | Type | Purpose |
|-----------|------|---------|
| `356092661742-q9ilt7ficit09cstlq72qekve889rdib` | Android (Type 1) | Android app authentication |
| `356092661742-hcvah5tufmgv5eas4ao4ijqk0vope50o` | Web (Type 3) | Backend server authentication |

## Firebase Project
- **Project ID**: `local-pier-506805-g5`
- **Project Number**: `356092661742`
- **Package Name**: `com.hyperlocal.app`

## SHA-1 Certificate Fingerprint
```
cb4468974ec7f04767429b46d5e7a719a8172a80
```

## How to Update
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select project **local-pier-506805-g5**
3. Project Settings → Your apps → Download config
4. Replace this file and copy to all apps