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

## User-visible text

Every string a shopkeeper can see is defined **exactly once**, in
`lib/l10n/app_en.arb`, and reaches the screen through the generated
`AppLocalizations`. Business logic never produces sentences.

| Layer | May say | Never says |
| --- | --- | --- |
| domain / data / application | a **code** — `AppMessageCode`, `ProductFormFieldError`, or a structured descriptor (`core/l10n/relative_time.dart`) | `'Some sentence'` |
| widget layer | the resolved wording, via `appText(context)` | hand-written copy that duplicates the catalog |

```
AppMessageCode.sessionExpired  ->  appSessionExpired  ->  "Your session has expired."
ProductFormFieldError.mrpBelowPrice -> productFormErrorText -> "MRP cannot be lower ..."
```

* `core/errors/api_failure_text.dart` turns an `ApiFailure` into an
  `AppMessageCode`; `features/products/presentation/widgets/product_form_messages.dart`
  turns a `ProductFormFieldFailure` into a `String` for `FormField.validator`.
* `core/l10n/app_text.dart` resolves through the real delegate and falls back to
  the **generated** `AppLocalizationsEn` outside an app tree — so the ~40 test
  harnesses that pump a bare `MaterialApp` still see real catalog English and
  cannot drift from the `.arb`.
* Codes carry an `l10nKey` string rather than an import, keeping the domain
  layer free of Flutter.

Static labels and hints in widgets are still inline (`labelText: 'Brand'`,
tooltips, etc.). They are catalog candidates one screen at a time; nothing in
`lib/features/*/domain` returns a literal message.

```bash
flutter gen-l10n            # after editing lib/l10n/app_en.arb
flutter analyze --no-pub
flutter test
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
