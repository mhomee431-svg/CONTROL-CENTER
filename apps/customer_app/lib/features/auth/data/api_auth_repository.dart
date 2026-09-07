import '../../../core/error/failures.dart';
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
    try {
      await _apiClient.post(
        ApiEndpoints.sendOtp,
        data: {'phone_number': phoneNumber},
        requiresAuth: false,
      );
    } catch (e) {
      throw _mapToFailure(e, operation: 'send_otp');
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
    try {
      final data = await _apiClient.post(
        ApiEndpoints.verifyOtp,
        data: {
          'phone_number': phoneNumber,
          'otp': otpCode,
          'device_id': deviceId,
          'device_name': deviceName,
          'device_type': deviceType,
          'app_version': appVersion,
        },
        requiresAuth: false,
      );

      return _parseAuthResult(data);
    } catch (e) {
      throw _mapToFailure(e, operation: 'verify_otp');
    }
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
    try {
      final data = await _apiClient.post(
        ApiEndpoints.register,
        data: {
          'phone_number': phoneNumber,
          'otp': otpCode,
          'name': name,
          'device_id': deviceId,
          'device_name': deviceName,
          'device_type': deviceType,
          'app_version': appVersion,
        },
        requiresAuth: false,
      );

      return _parseAuthResult(data);
    } catch (e) {
      throw _mapToFailure(e, operation: 'register');
    }
  }

  @override
  Future<AuthResult> refreshToken(String refreshToken, {String? deviceId}) async {
    try {
      final data = await _apiClient.post(
        ApiEndpoints.refreshToken,
        data: {
          'refresh_token': refreshToken,
          'device_id': deviceId,
        },
        requiresAuth: false,
      );

      return _parseAuthResult(data);
    } catch (e) {
      throw _mapToFailure(e, operation: 'refresh');
    }
  }

  @override
  Future<void> logout({
    String? refreshToken,
    String? sessionId,
    bool revokeAll = false,
  }) async {
    try {
      await _apiClient.post(
        ApiEndpoints.logout,
        data: {
          'refresh_token': refreshToken,
          'session_id': sessionId,
          'revoke_all': revokeAll,
        },
      );
    } catch (e) {
      // Logout failure should never prevent local session clearing.
      // Swallow and let the caller clear local state.
    }
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
        isNewUser: (user?['is_new_user'] as bool?) ?? false,
      );
    }
    throw const ApiException(
      type: ApiErrorType.unknown,
      message: 'Invalid response from server',
    );
  }

  /// Map an HTTP/network exception into a domain [Failure].
  Failure _mapToFailure(Object e, {required String operation}) {
    if (e is ApiException) {
      switch (e.type) {
        case ApiErrorType.offline:
        case ApiErrorType.timeout:
          return const NetworkFailure();
        case ApiErrorType.unauthorized:
          return const SessionExpiredFailure();
        default:
          // For OTP-specific operations, map known backend error messages.
          final msg = e.message.toLowerCase();
          if (operation == 'verify_otp' || operation == 'register') {
            if (msg.contains('invalid otp')) return const InvalidOtpFailure();
            if (msg.contains('expired')) return const ExpiredOtpFailure();
            if (msg.contains('too many') || msg.contains('attempt')) {
              return const TooManyAttemptsFailure();
            }
          }
          if (operation == 'send_otp') {
            if (msg.contains('invalid phone')) return const InvalidPhoneNumberFailure();
            if (msg.contains('rate limit') || msg.contains('too many')) {
              return const OtpRateLimitFailure();
            }
          }
          return ServerFailure(e.message);
      }
    }
    if (e is Failure) return e;
    return ServerFailure('Unexpected error during $operation');
  }
}