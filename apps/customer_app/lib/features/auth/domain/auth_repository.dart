import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/env/env_config.dart';
import '../../../core/network/api_client.dart';
import '../data/api_auth_repository.dart';
import '../data/mock_auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  // Backend-integration seam: when an API base URL is configured at build
  // time (`--dart-define=API_BASE_URL=...`), use the real repository.
  // Otherwise fall back to the mock so auth flows stay fully usable during
  // local development — no UI changes are needed when swapping.
  if (EnvConfig.hasApiBaseUrl) {
    return ApiAuthRepository(ref.watch(apiClientProvider));
  }
  return MockAuthRepository();
});

/// Abstract contract for authentication data operations.
///
/// The UI must never talk to storage or HTTP directly. All auth-related
/// data access flows through this abstraction so the mock can be
/// transparently replaced by the real backend in the future.
abstract class AuthRepository {
  /// Send an OTP to the given phone number.
  ///
  /// Throws [Failure] subclasses (e.g. [InvalidPhoneNumberFailure],
  /// [OtpRateLimitFailure], [NetworkFailure]) on error.
  Future<void> sendOtp(String phoneNumber);

  /// Verify the OTP and return the full auth session (access + refresh tokens).
  ///
  /// Throws [Failure] subclasses (e.g. [InvalidOtpFailure],
  /// [ExpiredOtpFailure], [TooManyAttemptsFailure]) on error.
  Future<AuthResult> verifyOtp({
    required String phoneNumber,
    required String otpCode,
    String? deviceId,
    String? deviceName,
    String? deviceType,
    String? appVersion,
  });

  /// Optional registration-required flow. For first-time users who must
  /// complete a profile (e.g. name) before continuing.
  Future<AuthResult> register({
    required String phoneNumber,
    required String otpCode,
    required String name,
    String? deviceId,
    String? deviceName,
    String? deviceType,
    String? appVersion,
  });

  /// Refresh the access token using the refresh token.
  ///
  /// Returns the full result (the backend rotates the refresh token on every
  /// use — the caller MUST persist the new refresh token, not just the
  /// access token).
  Future<AuthResult> refreshToken(String refreshToken, {String? deviceId});

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
  /// Whether this is the user's first login (used for onboarding).
  final bool isNewUser;

  const AuthResult({
    required this.accessToken,
    required this.refreshToken,
    required this.sessionId,
    this.userId,
    this.phoneNumber,
    this.name,
    this.role,
    this.isNewUser = false,
  });
}

/// Serializable session payload persisted securely after authentication.
class AuthSession {
  final String accessToken;
  final String refreshToken;
  final String sessionId;
  final int? userId;
  final String? phoneNumber;
  final String? name;
  final String? role;
  final String? deviceId;

  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.sessionId,
    this.userId,
    this.phoneNumber,
    this.name,
    this.role,
    this.deviceId,
  });

  factory AuthSession.fromAuthResult(AuthResult result) => AuthSession(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        sessionId: result.sessionId,
        userId: result.userId,
        phoneNumber: result.phoneNumber,
        name: result.name,
        role: result.role,
      );

  bool get isValid => accessToken.isNotEmpty && sessionId.isNotEmpty;
}