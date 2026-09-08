import 'package:firebase_auth/firebase_auth.dart';

/// Result of a successful Firebase phone-OTP sign-in.
class PhoneAuthResult {
  const PhoneAuthResult({required this.idToken, required this.phoneNumber});

  /// Firebase ID token to send to the backend for verification.
  final String idToken;

  /// Phone number in E.164 format (e.g. +919999999999).
  final String phoneNumber;
}

/// Thrown when Firebase phone authentication fails.
class PhoneAuthException implements Exception {
  const PhoneAuthException(this.message, {this.code});
  final String message;
  final String? code;

  @override
  String toString() => 'PhoneAuthException($code): $message';
}

/// Firebase Phone Auth contract — sends the OTP via Google and verifies it
/// client-side. The backend never sends an SMS; it only verifies the resulting
/// Firebase ID token.
abstract class PhoneAuthService {
  Future<void> sendOtp({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(String message) onError,
  });

  Future<PhoneAuthResult> verifyOtp({required String smsCode});

  Future<void> signOut();
}

/// Production implementation backed by ``firebase_auth``.
class FirebasePhoneAuthService implements PhoneAuthService {
  FirebasePhoneAuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;
  String? _verificationId;

  @override
  Future<void> sendOtp({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(String message) onError,
  }) async {
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          try {
            await _auth.signInWithCredential(credential);
            onCodeSent('');
          } catch (e) {
            onError('Auto-verification failed: $e');
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          onError(_mapFirebaseError(e));
        },
        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId;
          onCodeSent(verificationId);
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
        timeout: const Duration(seconds: 60),
      );
    } on FirebaseAuthException catch (e) {
      onError(_mapFirebaseError(e));
    } catch (e) {
      onError('Unexpected error: $e');
    }
  }

  @override
  Future<PhoneAuthResult> verifyOtp({required String smsCode}) async {
    final verificationId = _verificationId;
    if (verificationId == null || verificationId.isEmpty) {
      throw const PhoneAuthException(
        'No verification in progress. Request a new code.',
        code: 'no_verification',
      );
    }
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      final userCred = await _auth.signInWithCredential(credential);
      final token = await userCred.user?.getIdToken();
      final phone = userCred.user?.phoneNumber;
      if (token == null) {
        throw const PhoneAuthException('Could not obtain Firebase ID token', code: 'no_token');
      }
      return PhoneAuthResult(idToken: token, phoneNumber: phone ?? '');
    } on FirebaseAuthException catch (e) {
      throw PhoneAuthException(_mapFirebaseError(e), code: e.code);
    } catch (e) {
      throw PhoneAuthException('Verification failed: $e');
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (_) {}
    _verificationId = null;
  }

  String _mapFirebaseError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-phone-number':
        return 'The phone number format is invalid. Use E.164 format like +919999999999.';
      case 'too-many-requests':
        return 'Too many requests. Please try again later.';
      case 'quota-exceeded':
        return 'SMS quota exceeded. Please try again later.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'operation-not-allowed':
        return 'Phone sign-in is not enabled in Firebase console.';
      case 'invalid-verification-code':
        return 'The OTP you entered is incorrect.';
      case 'invalid-verification-id':
        return 'The verification session expired. Request a new code.';
      case 'session-expired':
        return 'The OTP session expired. Request a new code.';
      case 'missing-phone-number':
        return 'Phone number is required.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      default:
        return e.message ?? 'Phone authentication failed (${e.code}).';
    }
  }
}

/// Insecure/in-memory fake used when no real backend / Firebase is configured
/// (mock mode, widget tests) — no Firebase dependency at runtime.
class FakePhoneAuthService implements PhoneAuthService {
  FakePhoneAuthService({this.shouldFail = false, this.fakeIdToken = 'fake-firebase-token'});

  bool shouldFail;
  String fakeIdToken;

  @override
  Future<void> sendOtp({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(String message) onError,
  }) async {
    if (shouldFail) {
      onError('Fake send failure');
      return;
    }
    onCodeSent('fake-verification-id');
  }

  @override
  Future<PhoneAuthResult> verifyOtp({required String smsCode}) async {
    if (shouldFail) {
      throw const PhoneAuthException('Fake verify failure', code: 'fake');
    }
    return PhoneAuthResult(idToken: fakeIdToken, phoneNumber: '+919999999999');
  }

  @override
  Future<void> signOut() async {}
}