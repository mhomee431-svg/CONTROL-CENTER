/// Firebase application options for the Shopkeeper App (flutterfire).
///
/// Values are the public config from `android/app/google-services.json`
/// (project `local-pier-506805-g5`). On Android the native plugin also reads
/// that file directly; providing options here keeps web/desktop consistent.
///
/// NOTE (web): a Firebase **Web app** must be registered in the Firebase
/// Console (Project settings → Your apps → Add web app) before Google
/// Sign-In works in a browser. Paste its `App ID` below.
///
/// Google OAuth Web Client ID:
/// 356092661742-hcvah5tufmgv5eas4ao4ijqk0vope50o.apps.googleusercontent.com
library;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class AppFirebaseOptions {
  const AppFirebaseOptions._();

  /// Google OAuth **web** client ID of this Firebase project (public value).
  /// Reused on Android as the Credential Manager `serverClientId` and on iOS as
  /// the Google Sign-In `CLIENT_ID` (see [iOS]).
  static const String googleOAuthClientId =
      '356092661742-hcvah5tufmgv5eas4ao4ijqk0vope50o.apps.googleusercontent.com';

  /// iOS bundle identifier — must match `PRODUCT_BUNDLE_IDENTIFIER` in
  /// `ios/Runner.xcodeproj/project.pbxproj` (and the bundle id the iOS app is
  /// registered with in the Firebase console).
  static const String iOSBundleId = 'com.hyperlocal.app';

  static final FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyATSoTQd5Fepy53aYYYot3l72RAHIz61Ro',
    appId: '1:356092661742:android:dd589bd7bd86ecf54788ff',
    messagingSenderId: '356092661742',
    projectId: 'local-pier-506805-g5',
    storageBucket: 'local-pier-506805-g5.firebasestorage.app',
  );

  // ── iOS / desktop fallback (same project) ─────────────────────────────────
  // `iosClientId` is the Google **web** OAuth client — the same client the
  // Android Credential Manager path passes as `serverClientId`. firebase_core
  // forwards it to the native SDK as `CLIENT_ID`, which is what Google
  // Sign-In (OAuth provider flow) and the Phone-Auth reCAPTCHA fallback read
  // on iOS. The reversed form of this ID must be registered as a
  // `CFBundleURLTypes` scheme in `ios/Runner/Info.plist` so the browser can
  // hand the OAuth result back to the app.
  //
  // `iosBundleId` must equal `PRODUCT_BUNDLE_IDENTIFIER` in
  // `ios/Runner.xcodeproj/project.pbxproj` — and the bundle id the iOS app is
  // registered with in the Firebase console.
  static final FirebaseOptions iOS = FirebaseOptions(
    apiKey: 'AIzaSyATSoTQd5Fepy53aYYYot3l72RAHIz61Ro',
    appId: '1:356092661742:ios:340daaec77ba2c0e',
    messagingSenderId: '356092661742',
    projectId: 'local-pier-506805-g5',
    storageBucket: 'local-pier-506805-g5.firebasestorage.app',
    iosClientId: googleOAuthClientId,
    iosBundleId: iOSBundleId,
  );

  // ── Web ───────────────────────────────────────────────────────────────────
  // TODO(customer): register a Firebase Web app in the Console and paste its
  // App ID below. The apiKey/authDomain are public and already correct.
  static final FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyATSoTQd5Fepy53aYYYot3l72RAHIz61Ro',
    appId: '1:356092661742:web:356092661742',
    messagingSenderId: '356092661742',
    projectId: 'local-pier-506805-g5',
    authDomain: 'local-pier-506805-g5.firebaseapp.com',
    storageBucket: 'local-pier-506805-g5.firebasestorage.app',
  );

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.fuchsia => android,
      TargetPlatform.iOS || TargetPlatform.macOS => iOS,
      _ => web,
    };
  }
}