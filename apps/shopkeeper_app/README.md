# hyperlocal_shopkeeper_app

Shop management console for shopkeepers (Flutter). Targets **Android** and
**iOS** from the same codebase.

## Platforms

| Platform | Status | Notes |
| --- | --- | --- |
| Android | Active | Credential Manager Google Sign-In (`MainActivity.kt`), Firebase via `android/app/google-services.json` (`com.hyperlocal.app`). |
| iOS | Configured | Scaffold + `Info.plist` permissions + bundle id `com.hyperlocal.app`; Google Sign-In runs through Firebase's OAuth provider flow. Building requires macOS/Xcode — see **[docs/deployment/IOS_SETUP.md](../../docs/deployment/IOS_SETUP.md)**. |

```bash
flutter pub get
flutter run                 # Android device/emulator
flutter analyze lib test    # works on any host
flutter test                # works on any host (includes iOS config tests)
```

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
