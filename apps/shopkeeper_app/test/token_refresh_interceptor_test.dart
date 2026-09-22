// Token refresh — one reactive gate keeps an authenticated session alive.
//
// Every API call can outlive its access token: the app sits in the background,
// the token expires, and the first request back comes home 401. This suite
// proves `TokenRefreshInterceptor` (the lifecycle's token-refresh leg) recovers
// that request exactly once, rotates both tokens, dedupes concurrent 401s
// behind ONE refresh, and — when the refresh itself fails — wipes the session
// and reports it instead of looping or leaving callers hanging.
import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hyperlocal_shopkeeper_app/core/network/token_refresh_interceptor.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';

/// One scripted HTTP answer.
class _ScriptedResponse {
  const _ScriptedResponse(this.statusCode, {this.body = '{}'});
  final int statusCode;
  final String body;
}

/// What the test needs to remember about one request the interceptor made.
class _RecordedRequest {
  _RecordedRequest(RequestOptions options)
      : path = options.uri.toString(),
        authorization = options.headers['Authorization'] as String?,
        retried = options.extra['retried'] == true;

  final String path;
  final String? authorization;
  final bool retried;
}

/// A scripted [HttpClientAdapter]: each request consumes the next scripted
/// answer (asserting a loud failure if the script runs out).
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(List<_ScriptedResponse> script) : script = List.of(script);

  final List<_ScriptedResponse> script;
  final List<_RecordedRequest> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(_RecordedRequest(options));
    if (script.isEmpty) {
      fail('The test sent more requests than its script holds.');
    }
    final next = script.removeAt(0);
    return ResponseBody.fromString(
      next.body,
      next.statusCode,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

({TokenRefreshInterceptor interceptor, Dio dio, InMemoryTokenStore tokens,
    _ScriptedAdapter adapter, List<String> expired}) _harness({
  required List<_ScriptedResponse> script,
  String? refreshToken = 'old-refresh',
  Future<({String accessToken, String refreshToken})?> Function(
    String refreshToken,
  )? refresher,
}) {
  final tokens = InMemoryTokenStore(
    accessToken: 'old-access',
    refreshToken: refreshToken,
  );
  final adapter = _ScriptedAdapter(script);
  final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'))
    ..httpClientAdapter = adapter;
  final expired = <String>[];
  final interceptor = TokenRefreshInterceptor(
    dio: dio,
    tokenStore: tokens,
    onSessionExpired: () => expired.add('expired'),
    refresher: refresher,
  );
  dio.interceptors.add(interceptor);
  return (
    interceptor: interceptor,
    dio: dio,
    tokens: tokens,
    adapter: adapter,
    expired: expired,
  );
}



void main() {
  group('TokenRefreshInterceptor', () {
    test('a non-401 failure passes through untouched', () async {
      var refreshCalls = 0;
      final h = _harness(
        script: const [_ScriptedResponse(500, body: '{"message":"boom"}')],
        refresher: (_) async {
          refreshCalls++;
          return null;
        },
      );

      await expectLater(
        h.dio.get<Map<String, dynamic>>('/api/v1/shopkeeper/shops/10/products'),
        throwsA(isA<DioException>()),
      );

      // No refresh was attempted, the session was not touched, and the
      // request did not come back marked as retried.
      expect(refreshCalls, 0);
      expect(h.expired, isEmpty);
      expect(await h.tokens.readAccessToken(), 'old-access');
      expect(h.adapter.requests.single.retried, isFalse);
    });

    test('a 401 refreshes once and retries with the rotated token', () async {
      final h = _harness(
        script: const [
          _ScriptedResponse(401, body: '{"message":"token expired"}'),
          _ScriptedResponse(200, body: '{"items":[]}'),
        ],
        refresher: (refreshToken) async {
          expect(refreshToken, 'old-refresh');
          return (
            accessToken: 'new-access',
            refreshToken: 'rotated-refresh',
          );
        },
      );

      // The request goes out with the token the caller had in hand — the
      // same header the ApiClient attaches to every call.
      final response = await h.dio.get<Map<String, dynamic>>(
        '/api/v1/shopkeeper/shops/10/products',
        options: Options(headers: {'Authorization': 'Bearer old-access'}),
      );

      // The caller sees the RETRY's success, not the original 401.
      expect(response.statusCode, 200);
      expect(h.adapter.requests, hasLength(2));
      expect(h.adapter.requests.first.authorization, 'Bearer old-access');
      expect(h.adapter.requests.last.authorization, 'Bearer new-access');
      expect(h.adapter.requests.last.retried, isTrue);
      // BOTH tokens were rotated and stored for later requests.
      expect(await h.tokens.readAccessToken(), 'new-access');
      expect(await h.tokens.readRefreshToken(), 'rotated-refresh');
      expect(h.expired, isEmpty);
    });

    test('a failed refresh wipes the session and reports it exactly once',
        () async {
      var refreshCalls = 0;
      final h = _harness(
        script: const [_ScriptedResponse(401)],
        refresher: (_) async {
          refreshCalls++;
          return null;
        },
      );

      await expectLater(
        h.dio.get<Map<String, dynamic>>('/api/v1/shopkeeper/shops/10/products'),
        throwsA(isA<DioException>()),
      );

      // The session is gone (nothing left to retry with) and the auth flow
      // was told exactly once — no loops, no retries with dead tokens.
      expect(refreshCalls, 1);
      expect(await h.tokens.readAccessToken(), isNull);
      expect(await h.tokens.readRefreshToken(), isNull);
      expect(h.expired, hasLength(1));
      expect(h.adapter.requests, hasLength(1));
    });

    test('without a refresh token the session ends without a refresh call',
        () async {
      var refreshCalls = 0;
      final h = _harness(
        script: const [_ScriptedResponse(401)],
        refreshToken: null,
        refresher: (_) async {
          refreshCalls++;
          return null;
        },
      );

      await expectLater(
        h.dio.get<Map<String, dynamic>>('/api/v1/shopkeeper/shops/10/products'),
        throwsA(isA<DioException>()),
      );

      expect(refreshCalls, 0);
      expect(await h.tokens.readAccessToken(), isNull);
      expect(h.expired, hasLength(1));
      expect(h.adapter.requests, hasLength(1));
    });

    test('a refresh whose retry STILL 401s gives up instead of looping',
        () async {
      var refreshCalls = 0;
      final h = _harness(
        script: const [
          _ScriptedResponse(401),
          _ScriptedResponse(401),
        ],
        refresher: (_) async {
          refreshCalls++;
          return (accessToken: 'new-access', refreshToken: 'old-refresh');
        },
      );

      await expectLater(
        h.dio
            .get<Map<String, dynamic>>('/api/v1/shopkeeper/shops/10/products'),
        throwsA(isA<DioException>()),
      );

      // Exactly one refresh, one retry, then the session is ended — never an
      // infinite 401 → refresh → 401 loop.
      expect(refreshCalls, 1);
      expect(h.adapter.requests, hasLength(2));
      expect(await h.tokens.readAccessToken(), isNull);
      expect(h.expired, hasLength(1));
    });

    test('concurrent 401s share ONE refresh and both retry', () async {
      var refreshCalls = 0;
      final h = _harness(
        script: const [
          _ScriptedResponse(401),
          _ScriptedResponse(401),
          _ScriptedResponse(200, body: '{"a":1}'),
          _ScriptedResponse(200, body: '{"b":2}'),
        ],
        refresher: (_) async {
          refreshCalls++;
          // Outlast the second 401's arrival so it must queue, not refresh.
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return (accessToken: 'shared-access', refreshToken: 'old-refresh');
        },
      );

      final results = await Future.wait([
        h.dio.get<Map<String, dynamic>>('/a'),
        h.dio.get<Map<String, dynamic>>('/b'),
      ]);

      // One refresh served both callers; each retry carried the SAME
      // rotated token.
      expect(refreshCalls, 1);
      expect(results, hasLength(2));
      expect(h.adapter.requests, hasLength(4));
      final retried = h.adapter.requests.where((r) => r.retried).toList();
      expect(retried, hasLength(2));
      for (final request in retried) {
        expect(request.authorization, 'Bearer shared-access');
      }
      expect(h.expired, isEmpty);
      expect(await h.tokens.readAccessToken(), 'shared-access');
    });

    test('a queued request is released even when the shared refresh FAILS',
        () async {
      var refreshCalls = 0;
      final h = _harness(
        script: const [
          _ScriptedResponse(401),
          _ScriptedResponse(401),
        ],
        refresher: (_) async {
          refreshCalls++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return null;
        },
      );

      // Both callers must COMPLETE (not hang) when the shared refresh fails.
      final outcomes = await Future.wait([
        h.dio
            .get<Map<String, dynamic>>('/a')
            .then<dynamic>((_) => 'resolved')
            .catchError((_) => 'failed'),
        h.dio
            .get<Map<String, dynamic>>('/b')
            .then<dynamic>((_) => 'resolved')
            .catchError((_) => 'failed'),
      ]).timeout(const Duration(seconds: 5));

      // The queued second request failed through with its own error instead
      // of hanging on a handler that was never completed.
      expect(outcomes, everyElement('failed'));
      expect(refreshCalls, 1);
      expect(await h.tokens.readAccessToken(), isNull);
      expect(h.expired, hasLength(1));
      expect(h.adapter.requests, hasLength(2));
    });
  });
}
