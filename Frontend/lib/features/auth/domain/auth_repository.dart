import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../data/api_auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return ApiAuthRepository(ref.watch(apiClientProvider));
});

abstract class AuthRepository {
  /// Send an OTP to the given phone number.
  Future<void> sendOtp(String phoneNumber);

  /// Verify the OTP and return the full auth session (access + refresh tokens).
  Future<AuthResult> verifyOtp({
    required String phoneNumber,
    required String otpCode,
    String? deviceId,
    String? deviceName,
    String? deviceType,
    String? appVersion,
  });

  /// Refresh the access token using the refresh token.
  Future<String?> refreshToken(String refreshToken, {String? deviceId});

  /// Logout (revoke the session).
  Future<void> logout({
    String? refreshToken,
    String? sessionId,
    bool revokeAll = false,
  });
}

/// Result of a successful authentication/refresh.
class AuthResult {
  final String accessToken;
  final String refreshToken;
  final String sessionId;
  final int? userId;
  final String? phoneNumber;
  final String? name;
  final String? role;

  const AuthResult({
    required this.accessToken,
    required this.refreshToken,
    required this.sessionId,
    this.userId,
    this.phoneNumber,
    this.name,
    this.role,
  });
}