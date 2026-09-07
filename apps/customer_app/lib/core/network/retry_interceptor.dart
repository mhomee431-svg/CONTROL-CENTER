import 'dart:async';
import 'package:dio/dio.dart';
import '../security/safe_logger.dart';

/// Interceptor that automatically retries failed **idempotent** requests
/// (GET/HEAD) for transient failures (timeouts, 5xx server errors,
/// connection drops) with exponential backoff.
///
/// Non-idempotent requests (POST/PUT/DELETE) are never auto-retried —
/// see [shouldRetry].
class ExponentialRetryInterceptor extends Interceptor {
  final Dio dio;
  final int maxRetries;
  final Duration initialDelay;

  ExponentialRetryInterceptor({
    required this.dio,
    this.maxRetries = 3,
    this.initialDelay = const Duration(milliseconds: 800),
  });

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final requestOptions = err.requestOptions;
    final retries = requestOptions.extra['retry_count'] ?? 0;

    if (shouldRetry(err) && retries < maxRetries) {
      requestOptions.extra['retry_count'] = retries + 1;
      final delay = initialDelay * (1 << retries); // Exponential backoff: 800ms, 1600ms, 3200ms

      SafeLogger.warning(
        'Retrying request [${requestOptions.path}] (Attempt ${retries + 1}/$maxRetries) in ${delay.inMilliseconds}ms...',
      );

      await Future.delayed(delay);

      try {
        final response = await dio.fetch(requestOptions);
        return handler.resolve(response);
      } on DioException catch (retryErr) {
        return super.onError(retryErr, handler);
      }
    }

    return super.onError(err, handler);
  }

  /// Only idempotent requests are eligible for automatic retries.
  ///
  /// Retrying POST/PUT/DELETE can duplicate side effects (double OTP sends,
  /// duplicated saved items) when the first request actually reached the
  /// server but the response was lost, so those fail through immediately.
  static const Set<String> _idempotentMethods = {'GET', 'HEAD'};

  bool shouldRetry(DioException err) {
    if (!_idempotentMethods
        .contains(err.requestOptions.method.toUpperCase())) {
      return false;
    }
    if (err.type == DioExceptionType.cancel) return false;
    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError) {
      return true;
    }
    final status = err.response?.statusCode;
    return status != null && (status >= 500 || status == 429);
  }
}