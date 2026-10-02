import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/security/safe_logger.dart';

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

/// Map a Firebase Phone Auth error code to a customer-friendly sentence.
///
/// This is the ONLY place phone-auth failures are translated: technical
/// Firebase codes/messages must never reach the UI. Callers keep the original
/// `code` on [PhoneAuthException] for programmatic handling only (e.g. the
/// repository maps `invalid-verification-code` to an "incorrect OTP" state).
String phoneAuthErrorMessage(String? code) {
  switch (code) {
    case 'invalid-phone-number':
    case 'missing-phone-number':
      return 'That phone number looks invalid. Check the number and try again.';
    case 'invalid-verification-code':
    case 'missing-verification-code':
      return 'Incorrect OTP. Please check the code and try again.';
    case 'invalid-verification-id':
    case 'session-expired':
    case 'no_verification':
      return "This OTP has expired. Tap 'Resend OTP' to get a new code.";
    case 'too-many-requests':
      return 'Too many attempts. Please wait a moment and try again.';
    case 'quota-exceeded':
      return 'SMS limit reached for now. Please try again later.';
    case 'user-disabled':
      return 'This account has been disabled. Contact support for help.';
    case 'operation-not-allowed':
    case 'app-not-authorized':
    case 'missing-client-identifier':
      return 'Phone sign-in is unavailable right now. Please try again later.';
    case 'network-request-failed':
      return 'Network error. Check your connection and try again.';
    case 'captcha-check-failed':
    case 'invalid-app-credential':
    case 'missing-app-credential':
      return 'Verification could not start on this device. Please try again.';
    case 'credential-already-in-use':
    case 'provider-already-linked':
    case 'user-mismatch':
    case 'account-exists-with-different-credential':
      return 'This number is linked to another account. Sign in with that method instead.';
    case 'no_token':
      return 'We could not finish signing you in. Please try again.';
    default:
      return 'We could not verify your number right now. Please try again.';
  }
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

  /// Drops any in-flight verification state. Called when the customer backs
  /// out of the OTP screen (cancelled flow) so a stale session can never
  /// complete later. Implementations may no-op.
  Future<void> cancelPendingVerification() async {}
}

/// Production implementation backed by ``firebase_auth``.
class FirebasePhoneAuthService implements PhoneAuthService {
  FirebasePhoneAuthService({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;
  String? _verificationId;

  /// Phone number of the in-flight verification, so a repeat request for the
  /// same number is recognised as a resend.
  String? _lastPhoneNumber;

  /// Firebase's `forceResendingToken` for the in-flight verification. Reusing
  /// it lets the SDK re-send the SMS without re-running the (throttled)
  /// reCAPTCHA / Play-Integrity verification.
  int? _resendToken;

  /// Result captured when the platform auto-verifies the number (Android
  /// instant verification / iOS silent APNs push) — the customer never types
  /// the code, so a later [verifyOtp] call hands this result straight back.
  PhoneAuthResult? _autoVerifiedResult;

  @override
  Future<void> sendOtp({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(String message) onError,
  }) async {
    // Resend path: same number requested again after a code was already sent.
    final isResend = _lastPhoneNumber == phoneNumber && _resendToken != null;
    _lastPhoneNumber = phoneNumber;
    _verificationId = null;
    _autoVerifiedResult = null;

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        forceResendingToken: isResend ? _resendToken : null,
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Auto-verification is best-effort: capture the result so the
          // pending verifyOtp() can complete WITHOUT the customer typing a
          // code. Failures stay silent — manual code entry still works.
          try {
            final userCred = await _auth.signInWithCredential(credential);
            final token = await userCred.user?.getIdToken();
            if (token != null && token.isNotEmpty) {
              _autoVerifiedResult = PhoneAuthResult(
                idToken: token,
                phoneNumber: userCred.user?.phoneNumber ?? phoneNumber,
              );
              onCodeSent('');
            }
          } catch (_) {
            // Ignored on purpose — never surface technical auto-verify errors.
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          onError(phoneAuthErrorMessage(e.code));
        },
        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId;
          if (resendToken != null) _resendToken = resendToken;
          onCodeSent(verificationId);
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
        timeout: const Duration(seconds: 60),
      );
    } on FirebaseAuthException catch (e) {
      onError(phoneAuthErrorMessage(e.code));
    } catch (_) {
      onError(phoneAuthErrorMessage(null));
    }
  }

  @override
  Future<PhoneAuthResult> verifyOtp({required String smsCode}) async {
    // The platform may already have auto-verified this number — hand that
    // result straight back so no code entry is required.
    final autoVerified = _autoVerifiedResult;
    if (autoVerified != null) {
      _autoVerifiedResult = null;
      return autoVerified;
    }

    final verificationId = _verificationId;
    if (verificationId == null || verificationId.isEmpty) {
      throw PhoneAuthException(
        phoneAuthErrorMessage('no_verification'),
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
      if (token == null || token.isEmpty) {
        throw PhoneAuthException(
          phoneAuthErrorMessage('no_token'),
          code: 'no_token',
        );
      }
      return PhoneAuthResult(
        idToken: token,
        phoneNumber: phone ?? _lastPhoneNumber ?? '',
      );
    } on FirebaseAuthException catch (e) {
      throw PhoneAuthException(phoneAuthErrorMessage(e.code), code: e.code);
    } on PhoneAuthException {
      rethrow;
    } catch (_) {
      throw PhoneAuthException(
        phoneAuthErrorMessage(null),
        code: 'verify-failed',
      );
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      // Best-effort: the local verification state is cleared below regardless,
      // so a failed provider sign-out can never strand the phone flow.
      SafeLogger.debug('Firebase sign-out failed: $e');
    }
    await cancelPendingVerification();
  }

  @override
  Future<void> cancelPendingVerification() async {
    // No Firebase call is needed: an abandoned verification simply expires
    // server-side. Dropping the local state guarantees a stale verification
    // can never complete after the customer backs out.
    _verificationId = null;
    _resendToken = null;
    _lastPhoneNumber = null;
    _autoVerifiedResult = null;
  }
}

/// Insecure/in-memory fake used when no real backend / Firebase is configured
/// (mock mode, widget tests) — no Firebase dependency at runtime.
class FakePhoneAuthService implements PhoneAuthService {
  FakePhoneAuthService({
    this.shouldFail = false,
    this.fakeIdToken = 'fake-firebase-token',
  });

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

  @override
  Future<void> cancelPendingVerification() async {}
}
