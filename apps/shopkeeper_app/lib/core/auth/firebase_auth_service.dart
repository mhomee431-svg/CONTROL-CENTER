import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
/// Result of a Firebase authentication attempt.
class FirebaseAuthResult {
  const FirebaseAuthResult({required this.user, required this.idToken});

  final User user;
  final String idToken;
}

/// How Google Sign-In is obtained on a given platform.
///
/// Google's "native" Google Sign-In on Android is the Credential Manager API,
/// which is implemented in `MainActivity.kt` behind a MethodChannel — it does
/// NOT exist on iOS. iOS therefore uses Firebase's own OAuth provider flow
/// (`OAuthProvider` + `ASWebAuthenticationSession`), which yields the exact
/// same Firebase ID token and needs no app-side native code.
enum GoogleSignInStrategy {
  /// Browser: Firebase JS SDK popup.
  webPopup,

  /// Android: native Credential Manager MethodChannel (`MainActivity.kt`).
  androidCredentialManager,

  /// iOS: Firebase OAuth provider flow (no MethodChannel involved).
  firebaseOAuthProvider,
}

/// Picks the Google Sign-In implementation for [platform].
///
/// Everything except iOS keeps the pre-existing path; unknown platforms fall
/// back to the credential-manager channel, whose missing-plugin error is turned
/// into an actionable message by [FirebaseAuthService.signInWithGoogle].
GoogleSignInStrategy googleSignInStrategyFor(TargetPlatform platform) =>
    switch (platform) {
      TargetPlatform.iOS => GoogleSignInStrategy.firebaseOAuthProvider,
      _ => GoogleSignInStrategy.androidCredentialManager,
    };

class FirebaseAuthService {
  FirebaseAuthService({FirebaseAuth? auth}) : _authOverride = auth;

  /// Optional test/runtime override. When null, [FirebaseAuth.instance] is
  /// resolved lazily at USE time — constructing the service (and reading
  /// [currentUser]) never crashes in tests without an initialised Firebase
  /// core; the device is simply treated as signed-out.
  final FirebaseAuth? _authOverride;

  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  static const _channel = MethodChannel('com.hyperlocal.app/google_auth');

  /// Firebase user on this device, or null when signed out / when the
  /// Firebase core is unavailable (unit tests, desktop without Firebase).
  User? get currentUser {
    try {
      return _auth.currentUser;
    } catch (_) {
      // Firebase core not initialised → treat the device as signed out.
      return null;
    }
  }

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Initialize (no-op for Credential Manager; the web SDK reads the app
  /// options set in main.dart).
  Future<void> initialize({String? serverClientId}) async {
    // Credential Manager is initialized natively in MainActivity on Android.
  }

  /// Sign in with Google. Returns a Firebase ID token + the Firebase user.
  ///
  /// The platform decides HOW the Google credential is obtained (see
  /// [GoogleSignInStrategy]); every path ends in the same Firebase session and
  /// the same ID-token contract, so the backend exchange is untouched.
  Future<FirebaseAuthResult> signInWithGoogle() async {
    debugPrint('  ├─ signInWithGoogle() called');
    debugPrint('  ├─ Platform: ${kIsWeb ? "web" : "native (Android/iOS)"}');
    if (kIsWeb) {
      debugPrint('  └─ Using web sign-in flow (popup)');
      return _signInWithGoogleWeb();
    }
    // iOS: the Android Credential Manager channel does not exist there, so the
    // credential comes from Firebase's own OAuth provider flow instead.
    final strategy = googleSignInStrategyFor(defaultTargetPlatform);
    debugPrint('  └─ Native flow: ${strategy.name}');
    if (strategy == GoogleSignInStrategy.firebaseOAuthProvider) {
      return _signInWithGoogleOAuthProvider();
    }
    return _signInWithGoogleNative();
  }

  /// iOS path: Firebase's own Google OAuth provider flow.
  ///
  /// `signInWithProvider` drives `OAuthProvider(providerID: "google.com")`
  /// through the system browser (`ASWebAuthenticationSession`), needing:
  ///   * `iosClientId` / `iosBundleId` in the Firebase options — forwarded to
  ///     the native SDK as `CLIENT_ID` / `BUNDLE_ID` (`lib/firebase_options.dart`);
  ///   * the REVERSED client ID registered as a `CFBundleURLTypes` scheme in
  ///     `ios/Runner/Info.plist`, so the browser can hand the result back.
  ///
  /// See `docs/deployment/IOS_SETUP.md` for the full checklist.
  Future<FirebaseAuthResult> _signInWithGoogleOAuthProvider() async {
    // Same reason as the Android path: drop a stale Firebase session first so a
    // cached invalid credential is never replayed.
    try {
      await signOut();
    } catch (_) {
      // Best-effort: continue with the fresh sign-in request.
    }
    try {
      final credential = await _auth.signInWithProvider(GoogleAuthProvider());
      return await _resultFrom(credential);
    } on FirebaseAuthException {
      rethrow;
    } on PlatformException catch (e) {
      // Browser-level failures surface through the plugin as PlatformException.
      throw FirebaseAuthException(
        code: e.code,
        message: e.message ?? 'Google Sign-In failed',
      );
    } on MissingPluginException {
      // firebase_auth unavailable on this platform — say so plainly.
      throw FirebaseAuthException(
        code: 'google-sign-in-unavailable',
        message: 'Google Sign-In is not available on this platform yet.',
      );
    }
  }

  Future<FirebaseAuthResult> _signInWithGoogleWeb() async {
    return _resultFrom(await _auth.signInWithPopup(GoogleAuthProvider()));
  }

  /// Normalises a Firebase [UserCredential] into the app's
  /// [FirebaseAuthResult] (Firebase user + freshly refreshed ID token) so every
  /// platform path ends in the identical result contract.
  Future<FirebaseAuthResult> _resultFrom(UserCredential credential) async {
    final user = credential.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'firebase-user-null',
        message: 'Firebase user is null after Google Sign-In',
      );
    }
    final idToken = await user.getIdToken(true);
    if (idToken == null || idToken.isEmpty) {
      throw FirebaseAuthException(
        code: 'id-token-null',
        message: 'No ID token returned from Google Sign-In',
      );
    }
    return FirebaseAuthResult(user: user, idToken: idToken);
  }

  Future<FirebaseAuthResult> _signInWithGoogleNative() async {
    try {
      // Clear any stale/cached Firebase session and invalid ID token before
      // requesting a fresh Google credential. Reusing a cached invalid token
      // causes "SignInWithIdp are blocked" style failures on repeated sign-in.
      debugPrint('  ├─ Clearing stale Firebase session (signOut)...');
      try {
        await signOut();
        debugPrint('  │  └─ signOut completed');
      } on FirebaseAuthException catch (e) {
        debugPrint('  │  └─ signOut failed (ignored): ${e.code}');
        // Best-effort: continue to the native sign-in even if sign-out fails.
      }

      debugPrint('  ├─ Invoking native MethodChannel: signInWithGoogle...');
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'signInWithGoogle',
      );
      debugPrint('  │  └─ MethodChannel returned: ${result != null ? "data" : "null"}');

      if (result == null) {
        debugPrint('  │  ✗ signInWithGoogle returned null (cancelled)');
        throw FirebaseAuthException(
          code: 'google-sign-in-cancelled',
          message: 'Google Sign-In was cancelled',
        );
      }

      final idToken = result['idToken'] as String?;
      debugPrint('  ├─ Extracted idToken: ${idToken != null && idToken.isNotEmpty ? "present (${idToken.length} chars)" : "null/empty"}');
      if (idToken == null || idToken.isEmpty) {
        debugPrint('  │  ✗ idToken is null or empty');
        throw FirebaseAuthException(
          code: 'id-token-null',
          message: 'No ID token returned from Google Sign-In',
        );
      }

      final user = _auth.currentUser;
      debugPrint('  ├─ Firebase currentUser: ${user != null ? "present (uid: ${user.uid})" : "null"}');
      if (user == null) {
        debugPrint('  │  ✗ Firebase user is null after native sign-in');
        throw FirebaseAuthException(
          code: 'firebase-user-null',
          message: 'Firebase user is null after native sign-in',
        );
      }

      debugPrint('  └─ FirebaseAuthResult ready: user=${user.uid}, token=${idToken.length} chars');
      return FirebaseAuthResult(user: user, idToken: idToken);
    } on MissingPluginException {
      // The Google-Auth channel is implemented in MainActivity.kt (Android
      // only). On iOS the flow runs through the Firebase OAuth provider path
      // instead, and on desktop there is no implementation at all — say so
      // plainly instead of failing with a generic message.
      debugPrint('Google Sign-In: native channel unavailable on this platform');
      throw FirebaseAuthException(
        code: 'google-sign-in-unavailable',
        message: 'Google Sign-In is not available on this platform yet.',
      );
    } on PlatformException catch (e) {
      final details = e.details ?? 'No details';
      debugPrint(
        'Google Sign-In PlatformException: code=${e.code}, message=${e.message}, details=$details',
      );
      if (e.code == 'NO_GOOGLE_ACCOUNTS') {
        throw FirebaseAuthException(
          code: 'no-google-accounts',
          message: e.message ?? 'No Google account on device. Add one in Settings → Accounts → Google.',
        );
      }
      if (e.code == 'GOOGLE_SIGN_IN_FAILED') {
        throw FirebaseAuthException(
          code: 'google-sign-in-failed',
          message: e.message ?? 'Google Sign-In failed',
        );
      }
      throw FirebaseAuthException(
        code: e.code,
        message: e.message ?? 'Google Sign-In failed',
      );
    }
  }

  /// Sign out of Firebase.
  Future<void> signOut() async {
    try {
      await _channel.invokeMethod('signOut');
    } on PlatformException {
      // Ignore native sign-out errors
    } catch (_) {
      // Native channel unavailable (tests/desktop) — ignore.
    }
    try {
      await _auth.signOut();
    } catch (_) {
      // Firebase core not initialised (tests/desktop) — nothing to clear.
    }
  }

  /// Get current user info from native side.
  Future<Map<String, dynamic>?> getCurrentUser() async {
    try {
      final result = await _channel.invokeMethod('getCurrentUser');
      if (result is Map) {
        return result.cast<String, dynamic>();
      }
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Refresh the ID token.
  Future<String?> refreshIdToken() async {
    return _auth.currentUser?.getIdToken(true);
  }
}

final firebaseAuthServiceProvider = Provider<FirebaseAuthService>((ref) {
  return FirebaseAuthService();
});
