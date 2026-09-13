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

class FirebaseAuthService {
  FirebaseAuthService({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;
  static const _channel = MethodChannel('com.hyperlocal.app/google_auth');

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Initialize (no-op for Credential Manager; the web SDK reads the app
  /// options set in main.dart).
  Future<void> initialize({String? serverClientId}) async {
    // Credential Manager is initialized natively in MainActivity on Android.
  }

  /// Sign in with Google. Returns a Firebase ID token + the Firebase user.
  Future<FirebaseAuthResult> signInWithGoogle() async {
    debugPrint('  ├─ signInWithGoogle() called');
    debugPrint('  ├─ Platform: ${kIsWeb ? "web" : "native (Android/iOS)"}');
    if (kIsWeb) {
      debugPrint('  └─ Using web sign-in flow (popup)');
      return _signInWithGoogleWeb();
    }
    debugPrint('  └─ Using native sign-in flow (Credential Manager)');
    return _signInWithGoogleNative();
  }

  Future<FirebaseAuthResult> _signInWithGoogleWeb() async {
    final credential = await _auth.signInWithPopup(GoogleAuthProvider());
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
    }
    await _auth.signOut();
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
