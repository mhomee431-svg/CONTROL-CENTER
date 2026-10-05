import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/network/retry_interceptor.dart';

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
        response: Response(requestOptions: requestOptions, statusCode: 503),
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
        response: Response(requestOptions: requestOptions, statusCode: 400),
      );

      expect(interceptor.shouldRetry(dioError), isFalse);
    });

    test('never retries non-idempotent POST requests on timeouts', () {
      // Retrying a POST whose response was lost could double-apply the
      // side effect (duplicate OTP send / duplicate save).
      final dio = Dio(BaseOptions(baseUrl: 'https://test.com'));
      final interceptor = ExponentialRetryInterceptor(
        dio: dio,
        maxRetries: 3,
        initialDelay: const Duration(milliseconds: 1),
      );

      final requestOptions = RequestOptions(
        path: '/auth/otp/send',
        method: 'POST',
      );
      final dioError = DioException(
        requestOptions: requestOptions,
        type: DioExceptionType.connectionTimeout,
      );

      expect(interceptor.shouldRetry(dioError), isFalse);
    });

    test('never retries non-idempotent POST requests on 5xx errors', () {
      final dio = Dio(BaseOptions(baseUrl: 'https://test.com'));
      final interceptor = ExponentialRetryInterceptor(
        dio: dio,
        maxRetries: 3,
        initialDelay: const Duration(milliseconds: 1),
      );

      final requestOptions = RequestOptions(
        path: '/saved/products',
        method: 'POST',
      );
      final dioError = DioException(
        requestOptions: requestOptions,
        type: DioExceptionType.badResponse,
        response: Response(requestOptions: requestOptions, statusCode: 503),
      );

      expect(interceptor.shouldRetry(dioError), isFalse);
    });
  });

  // ── A key is a PROMISE, not a guarantee ───────────────────────────────────
  //
  // These are the regression tests for the false-safety bug this file used to
  // encode. The earlier version asserted "a POST carrying the key is retried",
  // which is exactly the wrong rule: it made an HTTP header stand in for a
  // server-side guarantee. Auditing the backend found NO `Idempotency-Key`
  // header handling anywhere — its idempotency lives in request bodies
  // (`payload.idempotency_key`) on POS sync, merchant onboarding and inventory
  // import, none of which the customer app calls.
  //
  // So under the old rule, any mutation with the header set would have been
  // retried while the server performed the side effect a second time: two
  // charges, two order rows, two OTPs — for a request that LOOKS handled in
  // review. These tests pin the corrected rule: fail closed.
  group('a key alone does NOT unlock a mutation', () {
    const key = '3f6b1a2e-0c9d-4f21-9a1e-8b7c5d2e4f10';

    ExponentialRetryInterceptor buildInterceptor() =>
        ExponentialRetryInterceptor(
          dio: Dio(BaseOptions(baseUrl: 'https://test.com')),
          maxRetries: 3,
          initialDelay: const Duration(milliseconds: 1),
        );

    DioException keyed({
      required String method,
      required Map<String, dynamic> headers,
      String path = '/orders',
      int? status,
    }) {
      final options = RequestOptions(
        path: path,
        method: method,
        headers: headers,
      );
      return DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response(requestOptions: options, statusCode: status ?? 500),
      );
    }

    test('a POST carrying the key is still NOT retried', () {
      // THE regression. With no server-side handling, a retry here duplicates
      // the side effect. Failing closed is the only safe answer.
      expect(
        buildInterceptor().shouldRetry(
          keyed(method: 'POST', headers: {'Idempotency-Key': key}),
        ),
        isFalse,
        reason:
            'the backend does not read this header, so the key proves '
            'nothing and retrying would duplicate the mutation',
      );
    });

    test('a differently-cased header changes nothing either', () {
      // Header case must not become an accidental bypass of the allowlist.
      expect(
        buildInterceptor().shouldRetry(
          keyed(method: 'POST', headers: {'idempotency-key': key}),
        ),
        isFalse,
      );
    });

    test('a DELETE carrying the key is still NOT retried', () {
      // The most destructive method gets the same treatment.
      expect(
        buildInterceptor().shouldRetry(
          keyed(method: 'DELETE', headers: {'Idempotency-Key': key}),
        ),
        isFalse,
      );
    });

    test('an EMPTY key does not unlock a mutation', () {
      // The trap: a present-but-blank header looks like the key is set.
      expect(
        buildInterceptor().shouldRetry(
          keyed(method: 'POST', headers: {'Idempotency-Key': ''}),
        ),
        isFalse,
      );
    });

    test('a key never makes a non-transient 4xx retryable', () {
      // Even a confirmed contract makes a replay SAFE, not successful.
      expect(
        buildInterceptor().shouldRetry(
          keyed(method: 'POST', status: 400, headers: {'Idempotency-Key': key}),
        ),
        isFalse,
      );
    });

    test('markIdempotent attaches the key but does not grant safety', () {
      // The method still sets the header — it documents intent and travels with
      // the request — but callers must not read it as "now retryable".
      final options = RequestOptions(path: '/p', method: 'POST');
      ExponentialRetryInterceptor.markIdempotent(options, 'key-123');

      expect(options.headers['idempotency-key'], 'key-123');
      expect(
        buildInterceptor().shouldRetry(
          DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          ),
        ),
        isFalse,
        reason: 'attaching a key must not silently enable mutation retries',
      );
    });

    test('reads still retry with or without a key', () {
      // The point of failing closed on mutations is that reads stay reliable.
      expect(
        buildInterceptor().shouldRetry(keyed(method: 'GET', headers: const {})),
        isTrue,
      );
      expect(
        buildInterceptor().shouldRetry(
          keyed(method: 'GET', headers: {'Idempotency-Key': key}),
        ),
        isTrue,
      );
    });
  });
}
