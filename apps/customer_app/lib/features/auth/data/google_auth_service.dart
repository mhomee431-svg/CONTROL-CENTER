import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Result of a successful Google Sign-In.
class GoogleAuthResult {
  const GoogleAuthResult({required this.idToken, this.displayName, this.email});

  /// Firebase ID token to exchange with the backend (`/auth/google-login`).
  final String idToken;
  final String? displayName;
  final String? email;
}

/// Thrown when Google Sign-In fails.
class GoogleAuthException implements Exception {
  const GoogleAuthException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => 'GoogleAuthException($code): $message';
}

/// Map a Google Sign-In error code to a customer-friendly sentence.
///
/// The single translation point for Google auth failures: technical
/// Firebase/plugin messages must never reach the UI. The original `code`
/// stays on [GoogleAuthException] for programmatic handling only.
String googleAuthErrorMessage(String? code) {
  switch (code) {
    case 'cancelled':
    case 'canceled':
      return 'Google sign-in was cancelled.';
    case 'network-request-failed':
      return 'Network error. Check your connection and try again.';
    case 'account-exists-with-different-credential':
      return 'An account already exists with this email. Sign in with the original method.';
    case 'operation-not-allowed':
      return 'Google sign-in is unavailable right now. Please try again later.';
    case 'user-disabled':
      return 'This account has been disabled. Contact support for help.';
    case 'no-google-accounts':
      return 'No Google account found on this device. Add one in Settings, then try again.';
    case 'google-sign-in-unavailable':
      return 'Google Sign-In is not available on this device. Please use phone login.';
    case 'id-token-null':
    case 'firebase-user-null':
      return 'We could not complete Google sign-in. Please try again.';
    default:
      return 'Google Sign-In failed. Please try again.';
  }
}

/// Google Sign-In contract — returns a Firebase ID token that the backend
/// verifies server-side before issuing session tokens.
abstract class GoogleAuthService {
  Future<GoogleAuthResult> signInWithGoogle();

  Future<void> signOut();
}

/// Production implementation.
///
/// * Android: native Credential Manager via a MethodChannel implemented in
///   `MainActivity.kt` — the same strategy the shopkeeper app uses.
/// * iOS: Firebase's own OAuth provider flow (`ASWebAuthenticationSession`),
///   which yields the identical Firebase ID token and needs no native code.
/// * Web: Firebase JS SDK popup.
class FirebaseGoogleAuthService implements GoogleAuthService {
  FirebaseGoogleAuthService({FirebaseAuth? auth}) : _authOverride = auth;

  /// Optional test/runtime override. When null, [FirebaseAuth.instance] is
  /// resolved lazily at USE time so constructing this service never crashes
  /// before Firebase is initialised.
  final FirebaseAuth? _authOverride;

  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  static const MethodChannel _channel = MethodChannel(
    'com.hyperlocal.app/google_auth',
  );

  @override
  Future<GoogleAuthResult> signInWithGoogle() async {
    if (kIsWeb) {
      return _fromCredential(await _auth.signInWithPopup(GoogleAuthProvider()));
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return _signInWithOAuthProvider();
    }
    return _signInWithNativeAndroid();
  }

  /// iOS path: Firebase OAuth provider through the system browser.
  Future<GoogleAuthResult> _signInWithOAuthProvider() async {
    // Drop a stale Firebase session first so an invalid cached credential is
    // never replayed.
    try {
      await signOut();
    } catch (_) {}
    try {
      final credential = await _auth.signInWithProvider(GoogleAuthProvider());
      return await _fromCredential(credential);
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseError(e);
    } on PlatformException catch (e) {
      throw _mapPlatformError(e);
    } on MissingPluginException {
      throw GoogleAuthException(
        googleAuthErrorMessage('google-sign-in-unavailable'),
        code: 'google-sign-in-unavailable',
      );
    }
  }

  /// Android path: Credential Manager implemented natively in MainActivity.
  Future<GoogleAuthResult> _signInWithNativeAndroid() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'signInWithGoogle',
      );
      final idToken = result?['idToken'] as String?;
      if (idToken == null || idToken.isEmpty) {
        throw GoogleAuthException(
          googleAuthErrorMessage('id-token-null'),
          code: 'id-token-null',
        );
      }
      return GoogleAuthResult(
        idToken: idToken,
        displayName: result?['name'] as String?,
        email: result?['email'] as String?,
      );
    } on MissingPluginException {
      throw const GoogleAuthException(
        'Google Sign-In is not available on this platform yet.',
        code: 'google-sign-in-unavailable',
      );
    } on PlatformException catch (e) {
      throw _mapPlatformError(e);
    }
  }

  Future<GoogleAuthResult> _fromCredential(UserCredential credential) async {
    final user = credential.user;
    if (user == null) {
      throw GoogleAuthException(
        googleAuthErrorMessage('firebase-user-null'),
        code: 'firebase-user-null',
      );
    }
    final idToken = await user.getIdToken(true);
    if (idToken == null || idToken.isEmpty) {
      throw GoogleAuthException(
        googleAuthErrorMessage('id-token-null'),
        code: 'id-token-null',
      );
    }
    return GoogleAuthResult(
      idToken: idToken,
      displayName: user.displayName,
      email: user.email,
    );
  }

  GoogleAuthException _mapFirebaseError(FirebaseAuthException e) {
    // `canceled` (US spelling) is Firebase's actual code — normalise it so the
    // repository's cancellation check stays in one place.
    final code = e.code == 'canceled' ? 'cancelled' : e.code;
    return GoogleAuthException(googleAuthErrorMessage(e.code), code: code);
  }

  GoogleAuthException _mapPlatformError(PlatformException e) {
    // Never forward the plugin's raw message — only mapped, friendly copy.
    final raw = (e.message ?? '').toLowerCase();
    if (raw.contains('cancel')) {
      return GoogleAuthException(
        googleAuthErrorMessage('cancelled'),
        code: 'cancelled',
      );
    }
    if (e.code == 'NO_GOOGLE_ACCOUNTS') {
      return GoogleAuthException(
        googleAuthErrorMessage('no-google-accounts'),
        code: 'no-google-accounts',
      );
    }
    if (e.code == 'DEVELOPER_ERROR' || e.code == '10') {
      return GoogleAuthException(
        googleAuthErrorMessage('google-sign-in-unavailable'),
        code: 'google-sign-in-unavailable',
      );
    }
    return GoogleAuthException(
      googleAuthErrorMessage(null),
      code: 'google-sign-in-failed',
    );
  }

  @override
  Future<void> signOut() async {
    try {
      await _channel.invokeMethod<void>('signOut');
    } catch (_) {
      // Native channel unavailable (iOS/tests/desktop) — ignore.
    }
    try {
      await _auth.signOut();
    } catch (_) {
      // Firebase core not initialised (tests/desktop) — nothing to clear.
    }
  }
}

/// In-memory fake used when no real backend / Firebase is configured (mock
/// mode and widget tests) — keeps Google auth fully exercisable without a
/// Firebase project.
class FakeGoogleAuthService implements GoogleAuthService {
  FakeGoogleAuthService({
    this.shouldFail = false,
    this.cancelled = false,
    this.fakeIdToken = 'fake-google-firebase-token',
  });

  bool shouldFail;
  bool cancelled;
  String fakeIdToken;

  @override
  Future<GoogleAuthResult> signInWithGoogle() async {
    if (cancelled) {
      throw const GoogleAuthException(
        'Google sign-in was cancelled.',
        code: 'cancelled',
      );
    }
    if (shouldFail) {
      throw const GoogleAuthException(
        'Fake Google sign-in failure',
        code: 'google-sign-in-failed',
      );
    }
    return GoogleAuthResult(
      idToken: fakeIdToken,
      displayName: 'Test Google User',
      email: 'test.google@example.com',
    );
  }

  @override
  Future<void> signOut() async {}
}
