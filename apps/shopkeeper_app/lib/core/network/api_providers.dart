import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env_config.dart';
import 'api_client.dart';
import 'token_refresh_interceptor.dart';
import 'token_store.dart';

/// Global hook invoked whenever any API call fails with 401 (session
/// revoked/expired). The AuthController installs its sign-out transition
/// here at build time — a plain callback avoids circular provider deps.
void Function()? globalUnauthorizedHandler;

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
  dio.interceptors.add(TokenRefreshInterceptor(
    dio: dio,
    tokenStore: tokenStore,
    onSessionExpired: () => globalUnauthorizedHandler?.call(),
  ));

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