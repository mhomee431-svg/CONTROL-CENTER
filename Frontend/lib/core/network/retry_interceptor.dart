import 'dart:async';
import 'package:dio/dio.dart';
import '../security/safe_logger.dart';

/// Interceptor that automatically retries failed GET/POST requests 
/// for transient failures (timeouts, 5xx server errors, connection drops) with exponential backoff.
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

  bool shouldRetry(DioException err) {
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