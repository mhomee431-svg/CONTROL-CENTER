import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env_config.dart';
import 'api_client.dart';
import 'token_refresh_interceptor.dart';
import 'token_store.dart';

/// Global hook invoked whenever any API call fails with 401 (session
/// revoked/expired). The AuthController installs its sign-out transition
/// here at build time — a plain callback avoids circular provider deps.
void Function()? globalUnauthorizedHandler;

/// Request tracing header the backend honours: its `RequestContextMiddleware`
/// reads an incoming `X-Request-ID` (generating one when absent) and echoes
/// it on every response, so pairing this value with a backend log line
/// identifies the exact request on both sides.
const String kRequestIdHeader = 'X-Request-ID';

/// Stamps every outgoing backend request with a fresh `X-Request-ID`.
///
/// A stable per-request id (never re-sent on retries of the SAME request —
/// Dio reuses these options object across interceptor retries) lets the
/// backend's slow-request log (`request_id=…`) and access log point at one
/// mobile log line in a bug report.
class RequestIdInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // A caller-supplied id (tests) is respected; retries of the SAME request
    // reuse their options object, so a retry never mints a second id.
    options.headers.putIfAbsent(kRequestIdHeader, _newId);
    handler.next(options);
  }
}

/// Correlation key: millisecond timestamp + 32 random bits. It is a support
/// identifier, not a security token — `Random` is sufficient and adds no dep.
String _newId() {
  final now = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final rand = (_rand.nextDouble() * 0xFFFFFFFF).floor().toRadixString(36);
  return '$now-$rand';
}

final _rand = Random();

/// Emits one short line per request/response in debug builds only, so release
/// builds never leak URLs, tokens or payload shapes into device logs.
class DebugApiLogInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    debugPrint('[api] --> ${options.method} ${options.path}');
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    debugPrint(
      '[api] <-- ${response.statusCode} ${response.requestOptions.path}',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    debugPrint(
      '[api] <--> ${err.response?.statusCode ?? err.type} '
      '${err.requestOptions.path}',
    );
    handler.next(err);
  }
}

/// Single shared Dio instance for the Shopkeeper App.
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: EnvConfig.apiBaseUrl,
    // 30s connect + receive timeouts — the official app contract. This
    // guarantees the UI never hangs forever on a dead network / unreachable
    // backend (the #1 source of "infinite loading" bugs previously seen with
    // emulator-only base URLs). FastAPI + WiFi-direct normally answers in
    // <1s, so 30s is generous for slow links while still bounding the wait.
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
    responseType: ResponseType.json,
  ));

  // Add token refresh interceptor
  final tokenStore = ref.watch(tokenStoreProvider);
  dio.interceptors.addAll([
    RequestIdInterceptor(),
    if (kDebugMode) DebugApiLogInterceptor(),
    TokenRefreshInterceptor(
      dio: dio,
      tokenStore: tokenStore,
      onSessionExpired: () => globalUnauthorizedHandler?.call(),
    ),
  ]);

  return dio;
});

/// Shared API client.
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    dio: ref.watch(dioProvider),
    onUnauthorized: (_) => globalUnauthorizedHandler?.call(),
  );
});

/// Convenience provider resolving the stored bearer token.
final accessTokenProvider = FutureProvider<String?>((ref) async {
  return ref.watch(tokenStoreProvider).readAccessToken();
});