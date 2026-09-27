import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/network/api_error_handler.dart';

void main() {
  group('ApiException from DioException', () {
    test('correctly parses connection timeout', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/products'),
        type: DioExceptionType.connectionTimeout,
      );

      final apiException = ApiException.fromDioError(dioError);
      expect(apiException.type, equals(ApiErrorType.timeout));
      expect(apiException.message, contains('Connection timed out'));
    });

    test('correctly parses connection error as offline', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/products'),
        type: DioExceptionType.connectionError,
      );

      final apiException = ApiException.fromDioError(dioError);
      expect(apiException.type, equals(ApiErrorType.offline));
      expect(apiException.message, contains('No internet connection'));
    });

    test('correctly parses cancelled request', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/products'),
        type: DioExceptionType.cancel,
      );

      final apiException = ApiException.fromDioError(dioError);
      expect(apiException.type, equals(ApiErrorType.requestCancelled));
      expect(apiException.message, contains('cancelled'));
    });

    test('correctly parses 401 unauthorized', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/products'),
        response: Response(
          requestOptions: RequestOptions(path: '/products'),
          statusCode: 401,
        ),
        type: DioExceptionType.badResponse,
      );

      final apiException = ApiException.fromDioError(dioError);
      expect(apiException.type, equals(ApiErrorType.sessionExpired));
      expect(apiException.statusCode, equals(401));
      expect(apiException.message, contains('session has expired'));
    });

    test('correctly parses 404 not found', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/products'),
        response: Response(
          requestOptions: RequestOptions(path: '/products'),
          statusCode: 404,
        ),
        type: DioExceptionType.badResponse,
      );

      final apiException = ApiException.fromDioError(dioError);
      expect(apiException.type, equals(ApiErrorType.notFound));
      expect(apiException.statusCode, equals(404));
    });

    test('correctly parses 500 server error', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/products'),
        response: Response(
          requestOptions: RequestOptions(path: '/products'),
          statusCode: 500,
        ),
        type: DioExceptionType.badResponse,
      );

      final apiException = ApiException.fromDioError(dioError);
      expect(apiException.type, equals(ApiErrorType.serverError));
      expect(apiException.statusCode, equals(500));
      // Deliberately no "Server error" / "500" in the customer-facing string:
      // the code is recorded for logs, but showing it invites "so is it broken?"
      // and gives the customer nothing actionable.
      expect(apiException.message, isNot(contains('500')));
      expect(apiException.message, contains('try again'));
    });

    test('correctly handles unknown error', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/products'),
        message: 'Unexpected failure',
        type: DioExceptionType.unknown,
      );

      final apiException = ApiException.fromDioError(dioError);
      expect(apiException.type, equals(ApiErrorType.unknown));
      expect(apiException.message, contains('Unexpected failure'));
    });
  });

  // ── Spec table: every documented status code must be distinguishable ──────
  group('status code mapping', () {
    ApiException map(int code, {Object? body}) => ApiException.fromDioError(
      DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: code,
          data: body,
        ),
        type: DioExceptionType.badResponse,
      ),
    );

    test('401 is a session problem, not an access problem', () {
      final e = map(401);
      expect(e.type, ApiErrorType.sessionExpired);
      expect(e.requiresSignIn, isTrue);
      expect(e.message, contains('session has expired'));
    });

    test('403 is access denied and must not tell the customer to sign in', () {
      // Sending someone to the login screen for a 403 loops forever: they are
      // already authenticated and the answer will still be "no".
      final e = map(403);
      expect(e.type, ApiErrorType.accessDenied);
      expect(e.requiresSignIn, isFalse);
      expect(e.message, isNot(contains('sign in')));
    });

    test('404 reads as unavailable rather than a technical code', () {
      final e = map(404);
      expect(e.type, ApiErrorType.notFound);
      expect(e.message, isNot(contains('404')));
    });

    test('409 conflict is not retryable', () {
      // "You already did this" cannot be fixed by trying again.
      final e = map(409);
      expect(e.type, ApiErrorType.conflict);
      expect(e.isRetryable, isFalse);
    });

    test('422 prefers the backend field detail when it is safe', () {
      final e = map(422, body: {'message': 'Enter a 10-digit mobile number'});
      expect(e.type, ApiErrorType.validation);
      // Genuinely useful, safe copy — surfaced as-is.
      expect(e.message, 'Enter a 10-digit mobile number');
    });

    test('429 is rate limited and is not offered as a retry', () {
      final e = map(429);
      expect(e.type, ApiErrorType.rateLimited);
      // Retrying immediately is exactly what makes a 429 worse.
      expect(e.isRetryable, isFalse);
    });

    test('5xx becomes a readable server error with no code shown', () {
      for (final code in [500, 502, 503, 504]) {
        final e = map(code);
        expect(e.type, ApiErrorType.serverError, reason: 'code $code');
        expect(e.isRetryable, isTrue);
        expect(e.message, isNot(contains('$code')));
      }
    });

    test('a stack trace in the body never reaches the customer', () {
      final e = map(
        500,
        body: {
          'message':
              'Traceback (most recent call last):\n  File "app/main.py", line 42',
        },
      );
      expect(e.message, isNot(contains('Traceback')));
      expect(e.message, isNot(contains('main.py')));
    });

    test('a framework exception string in the body is discarded', () {
      final e = map(500, body: {'detail': 'KeyError: product_id not found'});
      expect(e.message, isNot(contains('KeyError')));
    });

    test('an unmodelled 4xx still yields safe copy', () {
      final e = map(405);
      expect(e.message, isNot(contains('405')));
      expect(e.type, ApiErrorType.unknown);
    });

    test('only genuinely retryable failures are marked retryable', () {
      expect(map(500).isRetryable, isTrue);
      expect(map(403).isRetryable, isFalse);
      expect(map(404).isRetryable, isFalse);
      expect(map(409).isRetryable, isFalse);
      expect(map(422).isRetryable, isFalse);
      expect(map(429).isRetryable, isFalse);
    });
  });

  group('isConnectivityError', () {
    test('treats network-shaped failures as connectivity problems', () {
      expect(
        isConnectivityError(
          const ApiException(type: ApiErrorType.offline, message: 'x'),
        ),
        isTrue,
      );
      expect(
        isConnectivityError(
          const ApiException(type: ApiErrorType.timeout, message: 'x'),
        ),
        isTrue,
      );
    });

    test('does not treat a 404 or 422 as an outage', () {
      // Both prove the network works. Reporting them as an outage would put a
      // false "You're offline" banner over a merely missing record.
      expect(
        isConnectivityError(
          const ApiException(type: ApiErrorType.notFound, message: 'x'),
        ),
        isFalse,
      );
      expect(
        isConnectivityError(
          const ApiException(type: ApiErrorType.validation, message: 'x'),
        ),
        isFalse,
      );
    });

    test('non-API errors are not connectivity errors', () {
      expect(isConnectivityError(Exception('boom')), isFalse);
      expect(isConnectivityError(null), isFalse);
    });
  });
}
