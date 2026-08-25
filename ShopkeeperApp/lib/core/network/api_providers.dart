import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env_config.dart';
import 'api_client.dart';
import 'token_store.dart';

/// Global hook invoked whenever any API call fails with 401 (session
/// revoked/expired). The AuthController installs its sign-out transition
/// here at build time — a plain callback avoids circular provider deps.
void Function()? globalUnauthorizedHandler;

/// Single shared Dio instance for the Shopkeeper App.
final dioProvider = Provider<Dio>((ref) {
  return Dio(BaseOptions(
    baseUrl: EnvConfig.apiBaseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    responseType: ResponseType.json,
  ));
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
