import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../env/env_config.dart';
import '../security/safe_logger.dart';
import 'retry_interceptor.dart';

final dioClientProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: EnvConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
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
    ),
  ]);

  return dio;
});