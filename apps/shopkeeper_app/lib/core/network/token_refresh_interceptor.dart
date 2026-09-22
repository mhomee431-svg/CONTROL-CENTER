import 'package:dio/dio.dart';

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

    /// Injectable refresh call for tests. The production refresh builds its
    /// own [Dio] (to avoid interceptor recursion), which a unit test cannot
    /// intercept — so a test passes [refresher] to stand in for the HTTP call
    /// and returns the rotated token pair (or null on failure). Production
    /// code leaves it unset and gets the real HTTP refresh unchanged.
    this.refresher,
  });

  final Dio dio;
  final TokenStore tokenStore;
  final void Function() onSessionExpired;

  /// Stand-in for the refresh HTTP call — see the constructor doc. Null in
  /// production, where `_refreshOverHttp` does the work.
  final Future<({String accessToken, String refreshToken})?> Function(
    String refreshToken,
  )? refresher;

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
        } catch (e) {
          handler.next(err);
        }
      } else {
        await _clearAndNotify();
        handler.next(err);
      }

      // Release everything that queued while the refresh was in flight. On
      // success each one retries with the rotated token; on failure each
      // re-reads the (now empty) store and fails through with its own
      // original error — a queued request must NEVER be left hanging with an
      // uncompleted handler just because the shared refresh failed.
      for (final retry in _pendingRequests) {
        retry();
      }
    } finally {
      _pendingRequests.clear();
    }
  }

  Future<bool> _refreshToken() async {
    final refreshToken = await tokenStore.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      return false;
    }

    // One place resolves the refresh: the injectable hook when a test
    // supplied one, the real HTTP call otherwise. Both answer with the
    // ROTATED token pair (or null on failure), and the pair is stored here —
    // the retry below always re-reads the store, so it can never send the
    // token that just failed.
    final refresher = this.refresher;
    final fresh = refresher != null
        ? await refresher(refreshToken)
        : await _refreshOverHttp(refreshToken);
    if (fresh == null) {
      return false;
    }

    await tokenStore.saveTokens(
      accessToken: fresh.accessToken,
      refreshToken: fresh.refreshToken,
    );

    return true;
  }

  /// The production refresh: one fresh [Dio] instance (so the refresh call
  /// never recurses through this interceptor), the backend's `refresh`
  /// endpoint, and the rotated pair parsed from the response's `data`.
  Future<({String accessToken, String refreshToken})?> _refreshOverHttp(
    String refreshToken,
  ) async {
    try {
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
        return null;
      }

      final data = body['data'];
      if (data is! Map<String, dynamic>) {
        return null;
      }

      final accessToken = data['access_token'] as String?;
      final newRefreshToken = data['refresh_token'] as String?;

      if (accessToken == null || accessToken.isEmpty) {
        return null;
      }

      return (
        accessToken: accessToken,
        // The backend rotates the refresh token; keep the old one only when
        // the response did not send a replacement.
        refreshToken: newRefreshToken ?? refreshToken,
      );
    } catch (e) {
      return null;
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
