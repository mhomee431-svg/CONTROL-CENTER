import '../domain/auth_repository.dart';
import '../../../core/error/failures.dart';

/// Mock backend implementation for local development and testing.
///
/// Simulates:
///  - Invalid phone numbers
///  - Invalid OTPs (`000000`)
///  - Expired OTPs (`111111`)
///  - Too-many-attempts (`222222`)
///  - Network failures (`333333`)
///  - First-time users (`444444` triggers isNewUser)
class MockAuthRepository implements AuthRepository {
  @override
  Future<void> sendOtp(String phoneNumber) async {
    await Future.delayed(
      const Duration(seconds: 2),
    ); // Simulate network latency

    if (phoneNumber.length < 10 || phoneNumber.length > 10) {
      throw const InvalidPhoneNumberFailure();
    }

    // `3333333333` simulates a network failure on send-OTP
    if (phoneNumber == '3333333333') {
      throw const NetworkFailure();
    }
  }

  @override
  Future<AuthResult> verifyOtp({
    required String phoneNumber,
    required String otpCode,
    String? deviceId,
    String? deviceName,
    String? deviceType,
    String? appVersion,
  }) async {
    await Future.delayed(const Duration(seconds: 2));

    if (otpCode == '000000') {
      throw const InvalidOtpFailure();
    }
    if (otpCode == '111111') {
      throw const ExpiredOtpFailure();
    }
    if (otpCode == '222222') {
      throw const TooManyAttemptsFailure();
    }
    if (otpCode == '333333') {
      throw const NetworkFailure();
    }

    // `444444` indicates a first-time user (registration-required flow)
    final isNewUser = otpCode == '444444';

    // Simulate successful login returning tokens
    return AuthResult(
      accessToken: 'mock_jwt_token_header.payload.signature',
      refreshToken: 'mock_refresh_token_value',
      sessionId: 'mock-session-id',
      userId: 1,
      phoneNumber: phoneNumber,
      name: 'Test User',
      role: 'customer',
      isNewUser: isNewUser,
    );
  }

  @override
  Future<AuthResult> signInWithGoogle({
    String? deviceId,
    String? deviceName,
    String? deviceType,
    String? appVersion,
  }) async {
    await Future.delayed(const Duration(seconds: 2));

    // Simulate a successful Google login returning backend session tokens.
    return const AuthResult(
      accessToken: 'mock_google_jwt_token_header.payload.signature',
      refreshToken: 'mock_refresh_token_value',
      sessionId: 'mock-session-id-google',
      userId: 3,
      name: 'Google Customer',
      role: 'customer',
    );
  }

  @override
  Future<AuthResult> register({
    required String phoneNumber,
    required String otpCode,
    required String name,
    String? deviceId,
    String? deviceName,
    String? deviceType,
    String? appVersion,
  }) async {
    await Future.delayed(const Duration(seconds: 2));

    if (otpCode == '000000') {
      throw const InvalidOtpFailure();
    }
    if (otpCode == '111111') {
      throw const ExpiredOtpFailure();
    }

    if (name.trim().isEmpty) {
      throw const ServerFailure('Name is required for registration');
    }

    return AuthResult(
      accessToken: 'mock_jwt_access_token_header.payload.signature',
      refreshToken: 'mock_refresh_token_value',
      sessionId: 'mock-session-id-registered',
      userId: 2,
      phoneNumber: phoneNumber,
      name: name.trim(),
      role: 'customer',
      isNewUser: true,
    );
  }

  @override
  Future<AuthResult> refreshToken(
    String refreshToken, {
    String? deviceId,
  }) async {
    await Future.delayed(const Duration(seconds: 1));
    return const AuthResult(
      accessToken: 'mock_refreshed_jwt_token_header.payload.signature',
      refreshToken: 'mock_refreshed_refresh_token_value',
      sessionId: 'mock-session-id',
      userId: 1,
      role: 'customer',
    );
  }

  @override
  Future<void> logout({
    String? refreshToken,
    String? sessionId,
    bool revokeAll = false,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));
  }
}
