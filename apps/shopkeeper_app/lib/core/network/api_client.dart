import 'package:dio/dio.dart';

/// Normalized API failure carrying HTTP status and backend error code.
class ApiException implements Exception {
  final int? statusCode;
  final String? errorCode;
  final String message;

  /// Raw `data` payload from the error envelope (if any). The barcode-lookup
  /// endpoint embeds the catalog matches inside a 300 / 404 error envelope,
  /// so callers can reconstruct the [BarcodeResolution] from this field.
  final dynamic data;

  const ApiException({
    this.statusCode,
    this.errorCode,
    required this.message,
    this.data,
  });

  /// True when the backend refused shop access (association/permission).
  bool get isForbidden => statusCode == 403;

  /// True when the session is no longer valid (401 unrecoverable).
  bool get isUnauthorized => statusCode == 401;

  factory ApiException.fromDioError(DioException e) {
    final response = e.response;
    final body = response?.data;
    String message = e.message ?? 'Network error';
    String? errorCode;
    dynamic errorData;
    if (body is Map) {
      final bodyMessage = body['message'];
      if (bodyMessage is String && bodyMessage.isNotEmpty) {
        message = bodyMessage;
      }
      final code = body['error_code'];
      if (code is String) errorCode = code;
      errorData = body['data'];
    }
    return ApiException(
      statusCode: response?.statusCode,
      errorCode: errorCode,
      message: message,
      data: errorData,
    );
  }

  @override
  String toString() => 'ApiException($statusCode, $errorCode): $message';
}

/// Thin Dio wrapper for the Shopkeeper backend:
///   - unwraps the `{success, message, data}` envelope
///   - maps failures to [ApiException]
///   - exposes [onUnauthorized] so the app can force sign-out on 401
///
/// Auth headers are attached by repositories (they hold the token store),
/// keeping this class free of storage dependencies.
class ApiClient {
  ApiClient({required this.dio, this.onUnauthorized});

  final Dio dio;

  /// Invoked when a request fails with 401 (session revoked/expired).
  final void Function(ApiException error)? onUnauthorized;

  Options _options(String? token) => Options(
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty)
            'Authorization': 'Bearer $token',
        },
      );

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    String? token,
  }) =>
      _send(() =>
          dio.get(path, queryParameters: query, options: _options(token)));

  Future<dynamic> post(String path, {Object? body, String? token}) =>
      _send(() => dio.post(path, data: body, options: _options(token)));

  Future<dynamic> put(String path, {Object? body, String? token}) =>
      _send(() => dio.put(path, data: body, options: _options(token)));

  Future<dynamic> patch(String path, {Object? body, String? token}) =>
      _send(() => dio.patch(path, data: body, options: _options(token)));

  Future<dynamic> delete(String path, {String? token}) =>
      _send(() => dio.delete(path, options: _options(token)));

  Future<dynamic> _send(Future<Response<dynamic>> Function() fn) async {
    try {
      final response = await fn();
      return _unwrap(response);
    } on DioException catch (e) {
      final mapped = ApiException.fromDioError(e);
      if (mapped.isUnauthorized) onUnauthorized?.call(mapped);
      throw mapped;
    }
  }

  dynamic _unwrap(Response<dynamic> response) {
    final body = response.data;
    if (body is Map<String, dynamic>) {
            if (body['success'] == true) return body['data'];
      throw ApiException(
        statusCode: response.statusCode,
        errorCode: body['error_code'] as String?,
        message: (body['message'] as String?) ?? 'Request failed',
        data: body['data'],
      );
    }
    return body;
  }
}
