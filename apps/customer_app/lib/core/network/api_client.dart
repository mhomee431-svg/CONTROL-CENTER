import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../env/env_config.dart';
import '../security/safe_logger.dart';
import '../storage/secure_storage_service.dart';
import 'api_endpoints.dart';
import 'api_error_handler.dart';
import 'connectivity_service.dart';
import 'retry_interceptor.dart';

/// A thin wrapper around Dio that:
/// - Injects the auth token on every request
/// - Handles token refresh on 401 (see [TokenRefreshInterceptor])
/// - Unwraps the common `{success, message, data}` response envelope
/// - Maps Dio errors to [ApiException]
class ApiClient {
  final Dio _dio;
  final SecureStorageService _storage;

  final StreamController<void> _sessionExpiredController =
      StreamController<void>.broadcast();

  ApiClient(this._dio, this._storage);

  /// Broadcast stream emitting whenever the stored session could not be
  /// recovered after a 401 (refresh rejected / revoked). The app listens to
  /// this to transition the customer into the signed-out state.
  Stream<void> get sessionExpiredEvents => _sessionExpiredController.stream;

  /// Flags the session as unrecoverable (called by [TokenRefreshInterceptor]).
  void notifySessionExpired() {
    SafeLogger.warning('Session expired — notifying listeners.');
    _sessionExpiredController.add(null);
  }

  /// Performs a GET request and returns the `data` field of the envelope.
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool requiresAuth = true,
  }) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.apiPath(path),
        queryParameters: queryParameters,
        options: await _buildOptions(requiresAuth),
      );
      return _unwrap(response);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// Performs a POST request and returns the `data` field of the envelope.
  Future<dynamic> post(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool requiresAuth = true,
  }) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.apiPath(path),
        data: data,
        queryParameters: queryParameters,
        options: await _buildOptions(requiresAuth),
      );
      return _unwrap(response);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// Performs a PUT request and returns the `data` field of the envelope.
  Future<dynamic> put(
    String path, {
    Object? data,
    bool requiresAuth = true,
  }) async {
    try {
      final response = await _dio.put(
        ApiEndpoints.apiPath(path),
        data: data,
        options: await _buildOptions(requiresAuth),
      );
      return _unwrap(response);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// Performs a DELETE request and returns the `data` field of the envelope.
  Future<dynamic> delete(String path, {bool requiresAuth = true}) async {
    try {
      final response = await _dio.delete(
        ApiEndpoints.apiPath(path),
        options: await _buildOptions(requiresAuth),
      );
      return _unwrap(response);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<Options> _buildOptions(bool requiresAuth) async {
    final options = Options(
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    );
    if (requiresAuth) {
      final token = await _storage.getToken();
      if (token != null) {
        options.headers!['Authorization'] = 'Bearer $token';
      }
    }
    return options;
  }

  /// Unwraps the common `{success, message, data}` envelope.
  dynamic _unwrap(Response response) {
    final body = response.data;
    if (body is Map<String, dynamic>) {
      final success = body['success'] ?? true;
      if (success == true) {
        return body['data'];
      }
      throw ApiException(
        type: ApiErrorType.unknown,
        message: body['message'] ?? 'Request failed',
        statusCode: response.statusCode,
      );
    }
    return body;
  }
}

/// Transparently refreshes an expired access token after a 401 and replays
/// the failed request once.
///
/// - **Single-flight**: concurrent 401s share one in-flight refresh call.
/// - Auth endpoints (`/auth/*`) never trigger a refresh — that would loop.
/// - On refresh failure the stored tokens are cleared and
///   [onSessionExpired] fires so the app can sign the customer out.
class TokenRefreshInterceptor extends Interceptor {
  final Dio _dio;
  final SecureStorageService _storage;
  final void Function()? _onSessionExpired;

  /// Shared, in-flight refresh future (single-flight guard).
  Future<bool>? _refreshing;

  TokenRefreshInterceptor(this._dio, this._storage, this._onSessionExpired);

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    final isUnauthorized = err.response?.statusCode == 401;
    final alreadyRetried = options.extra['retried_after_refresh'] == true;
    final isAuthCall = options.path.contains('/auth/');

    if (!isUnauthorized || alreadyRetried || isAuthCall) {
      return handler.next(err);
    }

    SafeLogger.debug('401 received — attempting token refresh.');
    final refreshed = await _refreshSingleFlight();
    if (!refreshed) {
      return handler.next(err);
    }

    try {
      final token = await _storage.getToken();
      if (token == null || token.isEmpty) {
        return handler.next(err);
      }
      options
        ..extra['retried_after_refresh'] = true
        ..headers['Authorization'] = 'Bearer $token';
      final replay = await _dio.fetch(options);
      return handler.resolve(replay);
    } on DioException catch (replayError) {
      return handler.next(replayError);
    }
  }

  /// Runs at most one refresh at a time; all callers await the same result.
  Future<bool> _refreshSingleFlight() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _doRefresh() async {
    final refreshToken = await _storage.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      _clearAndNotify();
      return false;
    }
    final deviceId = await _storage.getDeviceId();

    // A bare Dio instance without interceptors: a failing refresh must never
    // recurse into this interceptor again.
    final authDio = Dio(
      BaseOptions(
        baseUrl: EnvConfig.apiBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        responseType: ResponseType.json,
      ),
    );

    try {
      final response = await authDio.post(
        ApiEndpoints.apiPath(ApiEndpoints.refreshToken),
        data: {'refresh_token': refreshToken, 'device_id': deviceId},
        options: Options(
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
        ),
      );

      final body = response.data;
      if (body is! Map<String, dynamic> || body['success'] != true) {
        _clearAndNotify();
        return false;
      }
      final data = body['data'];
      if (data is! Map<String, dynamic>) {
        _clearAndNotify();
        return false;
      }

      final accessToken = data['access_token'] as String?;
      final newRefreshToken = data['refresh_token'] as String?;
      if (accessToken == null || accessToken.isEmpty) {
        _clearAndNotify();
        return false;
      }

      // Persist BOTH tokens: the backend rotates the refresh token on every
      // use; keeping the stale one would trip reuse-detection next time.
      await _storage.saveToken(accessToken);
      if (newRefreshToken != null && newRefreshToken.isNotEmpty) {
        await _storage.saveRefreshToken(newRefreshToken);
      }
      SafeLogger.debug('Token refresh succeeded.');
      return true;
    } catch (e) {
      SafeLogger.error('Token refresh failed.', e);
      _clearAndNotify();
      return false;
    } finally {
      authDio.close();
    }
  }

  Future<void> _clearAndNotify() async {
    await _storage.deleteToken();
    await _storage.deleteRefreshToken();
    await _storage.deleteSessionId();
    _onSessionExpired?.call();
  }
}

/// Correlation id for a single outbound request.
///
/// Time-based rather than random so it sorts chronologically in logs and stays
/// unique enough to trace one customer-reported failure without a UUID
/// dependency. Deliberately not derived from any token or user data.
String _newRequestId() {
  final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  return 'req_${now.toUpperCase()}';
}

/// Promotes connectivity to `online` after a successful response.
///
/// Guarded by [read] so this never *builds* the connectivity service in a
/// context that has not opted into it; a failure here must not take down a
/// request that actually succeeded.
Future<void> _confirmReachable(Ref ref) async {
  try {
    ref.read(connectivityServiceProvider).confirmReachable();
  } catch (_) {
    // Connectivity tracking is advisory; never let it break a good response.
  }
}

/// Marks connectivity as degraded after a network-shaped failure.
Future<void> _noteFailure(Ref ref) async {
  try {
    ref.read(connectivityServiceProvider).noteRequestFailure();
  } catch (_) {
    // As above — advisory only.
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: EnvConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      responseType: ResponseType.json,
    ),
  );

  final storage = ref.watch(secureStorageProvider);

  dio.interceptors.addAll([
    ExponentialRetryInterceptor(dio: dio),
    InterceptorsWrapper(
      // Stamps a correlation id on every outbound request so a customer
      // reporting "it failed at 14:32" can be traced to an exact request in
      // the logs, without logging bodies or tokens.
      onRequest: (options, handler) {
        options.headers['X-Request-ID'] ??= _newRequestId();
        SafeLogger.debug(
          'HTTP Outbound: [${options.method}] ${options.path} '
          '(${options.headers['X-Request-ID']})',
        );
        return handler.next(options);
      },
      onResponse: (response, handler) {
        SafeLogger.debug(
          'HTTP Inbound: [${response.statusCode}] ${response.requestOptions.path}',
        );
        // A response is the only proof that connectivity genuinely works, so it
        // is what promotes `reconnecting` back to `online`. Without this the
        // banner would sit on "Reconnecting…" forever even though requests are
        // succeeding again.
        unawaited(_confirmReachable(ref));
        return handler.next(response);
      },
      onError: (DioException e, handler) {
        SafeLogger.error(
          'HTTP Error: [${e.response?.statusCode}] ${e.requestOptions.path}',
        );
        // Only network-shaped failures mark the device offline. A 404 or a 422
        // proves the network works fine, and treating those as an outage would
        // show a false "You're offline" banner over a mere missing record.
        if (isConnectivityError(ApiException.fromDioError(e))) {
          unawaited(_noteFailure(ref));
        }
        return handler.next(e);
      },
    ),
  ]);

  final client = ApiClient(dio, storage);

  // Registered last so it sees errors only after logging/retry decided not
  // to handle them (Dio runs error interceptors in registration order).
  dio.interceptors.add(
    TokenRefreshInterceptor(dio, storage, client.notifySessionExpired),
  );

  ref.onDispose(client._sessionExpiredController.close);
  return client;
});
