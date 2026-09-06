import 'package:dio/dio.dart';

import 'api_client.dart';
import 'api_endpoints.dart';
import 'token_store.dart';

/// Intercepts 401 responses and attempts to refresh the access token.
/// On success, retries the original request with the new token.
/// On failure, clears tokens and notifies the app via [onSessionExpired].
class TokenRefreshInterceptor extends Interceptor {
  TokenRefreshInterceptor({
    required this.dio,
    required this.tokenStore,
    required this.onSessionExpired,
  });

  final Dio dio;
  final TokenStore tokenStore;
  final void Function() onSessionExpired;

  bool _isRefreshing = false;
  final List<void Function()> _pendingRequests = [];

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode != 401) {
      return handler.next(err);
    }

    // Already tried refresh and still 401 — give up
    if (err.requestOptions.extra['retried'] == true) {
      await _clearAndNotify();
      return handler.next(err);
    }

    if (_isRefreshing) {
      // Queue this request until refresh completes
      _pendingRequests.add(() async {
        final newToken = await tokenStore.readAccessToken();
        if (newToken != null) {
          err.requestOptions.headers['Authorization'] = 'Bearer $newToken';
          err.requestOptions.extra['retried'] = true;
          try {
            final response = await dio.fetch(err.requestOptions);
            return handler.resolve(response);
          } catch (e) {
            return handler.next(err);
          }
        }
        return handler.next(err);
      });
      return;
    }

    _isRefreshing = true;

    try {
      final success = await _refreshToken();
      _isRefreshing = false;

      if (success) {
        // Retry original request
        final newToken = await tokenStore.readAccessToken();
        err.requestOptions.headers['Authorization'] = 'Bearer $newToken';
        err.requestOptions.extra['retried'] = true;

        try {
          final response = await dio.fetch(err.requestOptions);
          handler.resolve(response);

          // Process pending requests
          for (final retry in _pendingRequests) {
            await retry();
          }
        } catch (e) {
          handler.next(err);
        }
      } else {
        await _clearAndNotify();
        handler.next(err);
      }
    } finally {
      _pendingRequests.clear();
    }
  }

  Future<bool> _refreshToken() async {
    try {
      final refreshToken = await tokenStore.readRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) {
        return false;
      }

      // Create a fresh Dio instance to avoid interceptor recursion
      final refreshDio = Dio(BaseOptions(
        baseUrl: _getBaseUrl(),
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        responseType: ResponseType.json,
      ));

      final response = await refreshDio.post(
        ApiEndpoints.refresh,
        data: {'refresh_token': refreshToken},
        options: Options(headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        }),
      );

      final body = response.data;
      if (body is! Map<String, dynamic> || body['success'] != true) {
        return false;
      }

      final data = body['data'];
      if (data is! Map<String, dynamic>) {
        return false;
      }

      final accessToken = data['access_token'] as String?;
      final newRefreshToken = data['refresh_token'] as String?;

      if (accessToken == null || accessToken.isEmpty) {
        return false;
      }

      // Save both tokens (refresh token is rotated)
      await tokenStore.saveTokens(
        accessToken: accessToken,
        refreshToken: newRefreshToken ?? refreshToken,
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> _clearAndNotify() async {
    await tokenStore.clearAll();
    onSessionExpired();
  }

  String _getBaseUrl() {
    // Extract base URL from the main Dio instance
    return dio.options.baseUrl;
  }
}
