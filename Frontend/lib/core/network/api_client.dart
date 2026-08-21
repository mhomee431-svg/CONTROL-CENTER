import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../env/env_config.dart';
import '../security/safe_logger.dart';
import '../storage/secure_storage_service.dart';
import 'api_error_handler.dart';
import 'retry_interceptor.dart';

/// A thin wrapper around Dio that:
/// - Injects the auth token on every request
/// - Handles token refresh on 401
/// - Unwraps the common `{success, message, data}` response envelope
/// - Maps Dio errors to [ApiException]
class ApiClient {
  final Dio _dio;
  final SecureStorageService _storage;

  ApiClient(this._dio, this._storage);

  /// Performs a GET request and returns the `data` field of the envelope.
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool requiresAuth = true,
  }) async {
    try {
      final response = await _dio.get(
        path,
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
        path,
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
        path,
        data: data,
        options: await _buildOptions(requiresAuth),
      );
      return _unwrap(response);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// Performs a DELETE request and returns the `data` field of the envelope.
  Future<dynamic> delete(
    String path, {
    bool requiresAuth = true,
  }) async {
    try {
      final response = await _dio.delete(
        path,
        options: await _buildOptions(requiresAuth),
      );
      return _unwrap(response);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<Options> _buildOptions(bool requiresAuth) async {
    final options = Options(
      headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
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

  dio.interceptors.addAll([
    ExponentialRetryInterceptor(dio: dio),
    InterceptorsWrapper(
      onRequest: (options, handler) {
        SafeLogger.debug('HTTP Outbound: [${options.method}] ${options.path}');
        return handler.next(options);
      },
      onResponse: (response, handler) {
        SafeLogger.debug('HTTP Inbound: [${response.statusCode}] ${response.requestOptions.path}');
        return handler.next(response);
      },
      onError: (DioException e, handler) {
        SafeLogger.error('HTTP Error: [${e.response?.statusCode}] ${e.requestOptions.path}');
        return handler.next(e);
      },
    ),
  ]);

  final storage = ref.watch(secureStorageProvider);
  return ApiClient(dio, storage);
});