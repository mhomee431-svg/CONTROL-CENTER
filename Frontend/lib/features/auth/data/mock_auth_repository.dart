import '../domain/auth_repository.dart';
import '../../../core/error/failures.dart';

class MockAuthRepository implements AuthRepository {
  @override
  Future<void> sendOtp(String phoneNumber) async {
    await Future.delayed(const Duration(seconds: 2)); // Simulate network latency
    if (phoneNumber.length < 10) {
      throw const ServerFailure('Invalid phone number format');
    }
    // Success scenario
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
      throw const ServerFailure('Invalid OTP entered');
    }
    if (otpCode == '111111') {
      throw const ServerFailure('OTP has expired');
    }

    // Simulate successful login returning tokens
    return AuthResult(
      accessToken: 'mock_jwt_token_header.payload.signature',
      refreshToken: 'mock_refresh_token_value',
      sessionId: 'mock-session-id',
      userId: 1,
      phoneNumber: phoneNumber,
      name: 'Test User',
      role: 'customer',
    );
  }

  @override
  Future<String?> refreshToken(String refreshToken, {String? deviceId}) async {
    await Future.delayed(const Duration(seconds: 1));
    return 'mock_refreshed_jwt_token_header.payload.signature';
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