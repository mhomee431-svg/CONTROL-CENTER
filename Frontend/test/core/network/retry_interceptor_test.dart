import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_customer_app/core/network/retry_interceptor.dart';

void main() {
  group('ExponentialRetryInterceptor', () {
    test('does not retry cancelled requests', () {
      final dio = Dio(BaseOptions(baseUrl: 'https://test.com'));
      final interceptor = ExponentialRetryInterceptor(
        dio: dio,
        maxRetries: 3,
        initialDelay: const Duration(milliseconds: 1),
      );

      final requestOptions = RequestOptions(path: '/products');
      final dioError = DioException(
        requestOptions: requestOptions,
        type: DioExceptionType.cancel,
      );

      expect(interceptor.shouldRetry(dioError), isFalse);
    });

    test('retries connection timeouts', () {
      final dio = Dio(BaseOptions(baseUrl: 'https://test.com'));
      final interceptor = ExponentialRetryInterceptor(
        dio: dio,
        maxRetries: 3,
        initialDelay: const Duration(milliseconds: 1),
      );

      final requestOptions = RequestOptions(path: '/products');
      final dioError = DioException(
        requestOptions: requestOptions,
        type: DioExceptionType.connectionTimeout,
      );

      expect(interceptor.shouldRetry(dioError), isTrue);
    });

    test('retries 5xx server errors', () {
      final dio = Dio(BaseOptions(baseUrl: 'https://test.com'));
      final interceptor = ExponentialRetryInterceptor(
        dio: dio,
        maxRetries: 3,
        initialDelay: const Duration(milliseconds: 1),
      );

      final requestOptions = RequestOptions(path: '/products');
      final dioError = DioException(
        requestOptions: requestOptions,
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: requestOptions,
          statusCode: 503,
        ),
      );

      expect(interceptor.shouldRetry(dioError), isTrue);
    });

    test('does not retry 400 bad request', () {
      final dio = Dio(BaseOptions(baseUrl: 'https://test.com'));
      final interceptor = ExponentialRetryInterceptor(
        dio: dio,
        maxRetries: 3,
        initialDelay: const Duration(milliseconds: 1),
      );

      final requestOptions = RequestOptions(path: '/products');
      final dioError = DioException(
        requestOptions: requestOptions,
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: requestOptions,
          statusCode: 400,
        ),
      );

      expect(interceptor.shouldRetry(dioError), isFalse);
    });
  });
}