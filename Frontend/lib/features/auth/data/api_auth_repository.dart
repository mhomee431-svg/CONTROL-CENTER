import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_error_handler.dart';
import '../domain/auth_repository.dart';

/// Real backend implementation of [AuthRepository].
class ApiAuthRepository implements AuthRepository {
  final ApiClient _apiClient;

  ApiAuthRepository(this._apiClient);

  @override
  Future<void> sendOtp(String phoneNumber) async {
    await _apiClient.post(
      ApiEndpoints.sendOtp,
      data: {'phone_number': phoneNumber},
      requiresAuth: false,
    );
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
    final data = await _apiClient.post(
      ApiEndpoints.verifyOtp,
      data: {
        'phone_number': phoneNumber,
        'otp': otpCode,
        'device_id': ?deviceId,
        'device_name': ?deviceName,
        'device_type': ?deviceType,
        'app_version': ?appVersion,
      },
      requiresAuth: false,
    );

    return _parseAuthResult(data);
  }

  @override
  Future<String?> refreshToken(String refreshToken, {String? deviceId}) async {
    final data = await _apiClient.post(
      ApiEndpoints.refreshToken,
      data: {
        'refresh_token': refreshToken,
        'device_id': ?deviceId,
      },
      requiresAuth: false,
    );

    final parsed = _parseAuthResult(data);
    return parsed.accessToken;
  }

  @override
  Future<void> logout({
    String? refreshToken,
    String? sessionId,
    bool revokeAll = false,
  }) async {
    await _apiClient.post(
      ApiEndpoints.logout,
      data: {
        'refresh_token': ?refreshToken,
        'session_id': ?sessionId,
        'revoke_all': revokeAll,
      },
    );
  }

  /// Parse the backend's success-response envelope into [AuthResult].
  AuthResult _parseAuthResult(dynamic data) {
    if (data is Map<String, dynamic>) {
      // Backend wraps in {success, message, data: {...}}
      final inner = data['data'] is Map<String, dynamic>
          ? data['data'] as Map<String, dynamic>
          : data;

      final accessToken = inner['access_token'] as String?;
      final refreshToken = inner['refresh_token'] as String?;
      final sessionId = inner['session_id'] as String?;

      if (accessToken == null) {
        throw const ApiException(
          type: ApiErrorType.unknown,
          message: 'Invalid response from server',
        );
      }

      final user = inner['user'] is Map<String, dynamic>
          ? inner['user'] as Map<String, dynamic>
          : null;

      return AuthResult(
        accessToken: accessToken,
        refreshToken: refreshToken ?? '',
        sessionId: sessionId ?? '',
        userId: user?['id'] as int?,
        phoneNumber: user?['phone_number'] as String?,
        name: user?['name'] as String?,
        role: user?['role'] as String?,
      );
    }
    throw const ApiException(
      type: ApiErrorType.unknown,
      message: 'Invalid response from server',
    );
  }
}