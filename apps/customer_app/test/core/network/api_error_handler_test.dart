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
      expect(apiException.type, equals(ApiErrorType.unauthorized));
      expect(apiException.statusCode, equals(401));
      expect(apiException.message, contains('Session expired'));
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
      expect(apiException.message, contains('Server error'));
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
}
