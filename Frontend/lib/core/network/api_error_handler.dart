import 'package:dio/dio.dart';

enum ApiErrorType {
  offline,
  timeout,
  unauthorized,
  notFound,
  serverError,
  requestCancelled,
  unknown,
}

class ApiException implements Exception {
  final ApiErrorType type;
  final String message;
  final int? statusCode;

  const ApiException({
    required this.type,
    required this.message,
    this.statusCode,
  });

  factory ApiException.fromDioError(DioException dioError) {
    if (dioError.type == DioExceptionType.cancel) {
      return const ApiException(
        type: ApiErrorType.requestCancelled,
        message: 'Request was cancelled.',
      );
    }

    if (dioError.type == DioExceptionType.connectionTimeout ||
        dioError.type == DioExceptionType.receiveTimeout ||
        dioError.type == DioExceptionType.sendTimeout) {
      return const ApiException(
        type: ApiErrorType.timeout,
        message: 'Connection timed out. Please check your internet connection and try again.',
      );
    }

    if (dioError.type == DioExceptionType.connectionError) {
      return const ApiException(
        type: ApiErrorType.offline,
        message: 'No internet connection detected. Please connect to Wi-Fi or mobile data.',
      );
    }

    final response = dioError.response;
    if (response != null) {
      final code = response.statusCode;
      if (code == 401 || code == 403) {
        return ApiException(
          type: ApiErrorType.unauthorized,
          statusCode: code,
          message: 'Session expired or unauthorized access. Please log in again.',
        );
      } else if (code == 404) {
        return ApiException(
          type: ApiErrorType.notFound,
          statusCode: code,
          message: 'The requested resource was not found.',
        );
      } else if (code != null && code >= 500) {
        return ApiException(
          type: ApiErrorType.serverError,
          statusCode: code,
          message: 'Server error encountered ($code). Our team has been notified.',
        );
      }
    }

    return ApiException(
      type: ApiErrorType.unknown,
      statusCode: response?.statusCode,
      message: dioError.message ?? 'An unexpected network error occurred.',
    );
  }

  @override
  String toString() => 'ApiException [$type]: $message (Status Code: $statusCode)';
}

/// Maps any thrown error into a user-safe message suitable for display.
///
/// Raw exception text (`Exception: ...`, stack fragments, internal URLs)
/// must never reach the UI — it leaks implementation details and reads
/// badly. Known [ApiException]s already carry human-friendly copy; anything
/// else collapses to a generic, actionable message.
String friendlyErrorMessage(Object? error) {
  if (error is ApiException) return error.message;
  return 'Something went wrong. Please check your connection and try again.';
}