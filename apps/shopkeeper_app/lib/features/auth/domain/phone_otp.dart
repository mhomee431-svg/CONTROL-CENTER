/// ── FUTURE (Phone OTP / SMS OTP) — FUNCTION SEAM ──────────────────────────
///
/// The MVP ships EXACTLY ONE sign-in method: Google Sign-In → Firebase
/// Authentication. Phone OTP is a FUTURE addition, so this seam is wired NOW
/// so that adding it later needs no rewrite:
///
///   Today (MVP)                     Future (Phone OTP)
///   ─────────────────────────       ─────────────────────────────────────
///   Google → Firebase  ──┐
///                        ├──→  Firebase ID token
///   SMS code → Firebase ─┘          →  /shopkeeper/auth/firebase-login
///                                   →  Session (same JWT pair, same storage)
///
/// Firebase issues ONE ID-token shape regardless of the provider that created
/// it, so the SMS-OTP path reuses the identical backend exchange, session
/// models, token storage, session restore and 401 handling that Google uses
/// today. Adding Phone OTP later therefore means:
///
///   1. provide a real [PhoneOtpService] (see `FirebasePhoneOtpService`),
///   2. enable [AuthMethod.phoneOtp] via `enabledAuthMethodsProvider`,
///   3. nothing else — the screen (`PhoneOtpScreen`), the controller method
///      (`AuthController.verifyPhoneOtp` / `loginWithPhoneOtp`) and the
///      repository contract already exist and are already covered by tests.
///
/// Deliberately NOT in the MVP: SMS OTP, a custom OTP service, password
/// authentication and a custom JWT login system.
library;

/// A pending SMS verification started by [PhoneOtpService.requestCode].
class PhoneOtpRequest {
  const PhoneOtpRequest({
    required this.phoneNumber,
    this.verificationId,
    this.resendToken,
    this.autoVerifiedIdToken,
  });

  /// E.164 number the code was sent to, e.g. `+919999999999`.
  final String phoneNumber;

  /// Provider session id handed back to [PhoneOtpService.verifyCode].
  final String? verificationId;

  /// Opaque token that lets the provider reuse the SMS session on a resend
  /// (Android `forceResendingToken`).
  final int? resendToken;

  /// Set when the platform verified the number WITHOUT user input (Android
  /// instant verification / iOS silent APNs push). The UI then skips code
  /// entry and signs in with this Firebase ID token directly.
  final String? autoVerifiedIdToken;

  /// True when the code step can be skipped entirely.
  bool get isAutoVerified =>
      autoVerifiedIdToken != null && autoVerifiedIdToken!.isNotEmpty;
}

/// Provider error already mapped to shopkeeper-readable text.
///
/// [code] keeps the raw provider code (e.g. `invalid-verification-code`) so
/// screens can offer targeted recovery later without touching the wording.
class PhoneOtpException implements Exception {
  const PhoneOtpException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => 'PhoneOtpException(${code ?? 'unknown'}): $message';
}

/// Provider-agnostic contract for SMS-OTP sign-in.
///
/// The concrete Firebase Phone Auth implementation lives in
/// `data/firebase_phone_otp_service.dart`; tests and offline development use
/// [MockPhoneOtpService]. Because the screen depends on THIS abstraction, the
/// OTP provider can be swapped (Firebase, a custom OTP service, MSG91, …)
/// without touching the UI, the controller or the session contract.
abstract class PhoneOtpService {
  /// False when the platform/build cannot send SMS codes (desktop, missing
  /// Firebase Phone Auth configuration). The UI then keeps offering Google.
  bool get isSupported;

  /// Sends — or re-sends, when [resendToken] is supplied — the SMS code.
  ///
  /// [e164PhoneNumber] is the canonical `+91…` form produced by
  /// `normalizeIndianPhone`.
  Future<PhoneOtpRequest> requestCode(
    String e164PhoneNumber, {
    int? resendToken,
  });

  /// Exchanges the typed code for a **Firebase ID token**, which is then sent
  /// to the backend through the same `/firebase-login` exchange as Google.
  Future<String> verifyCode({
    required String verificationId,
    required String code,
  });
}

/// Offline/dev [PhoneOtpService]: no SMS is sent and one fixed code is
/// accepted, exactly like `MockAuthRepository` for the rest of the app.
///
/// Used by `kUseMockAuth` builds and by the widget tests, which can therefore
/// exercise the complete OTP flow (request → verify → session) with no
/// Firebase, no SMS and no network.
class MockPhoneOtpService implements PhoneOtpService {
  MockPhoneOtpService({
    this.validCode = '123456',
    this.delay = const Duration(milliseconds: 400),
  });

  /// The only code this fake accepts.
  final String validCode;

  /// Simulated network latency.
  final Duration delay;

  int requestCalls = 0;
  int verifyCalls = 0;
  String? lastRequestedPhone;

  @override
  bool get isSupported => true;

  @override
  Future<PhoneOtpRequest> requestCode(
    String e164PhoneNumber, {
    int? resendToken,
  }) async {
    await Future<void>.delayed(delay);
    requestCalls++;
    lastRequestedPhone = e164PhoneNumber;
    return PhoneOtpRequest(
      phoneNumber: e164PhoneNumber,
      verificationId: 'mock-verification-id-$requestCalls',
      resendToken: resendToken,
    );
  }

  @override
  Future<String> verifyCode({
    required String verificationId,
    required String code,
  }) async {
    await Future<void>.delayed(delay);
    verifyCalls++;
    if (code != validCode) {
      throw const PhoneOtpException(
        'The code you entered is incorrect.',
        code: 'invalid-verification-code',
      );
    }
    return 'mock-phone-otp-id-token';
  }
}