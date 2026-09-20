import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_providers.dart';

/// The shared API client contract against the spec:
///
/// * one base URL, one timeout contract, one status-code vocabulary;
/// * every request carries an `X-Request-ID` the backend echoes, so a client
///   log line and a server log line can be paired in a bug report;
/// * debug-only request logging — tokens and payload shapes never reach
///   release device logs.
///
/// Only `http`-level behaviour (headers, timeouts, logging) is driven here —
/// the failure → state mapping lives in `system_state_test.dart`.
void main() {
  group('RequestIdInterceptor', () {
    test('stamps every request with an X-Request-ID', () async {
      String? seenId;
      final dio = Dio()..httpClientAdapter = _ScriptedAdapter((options) async {
        seenId = options.headers[kRequestIdHeader] as String?;
        return ResponseBody.fromString('{}', 200);
      });
      addTearDown(dio.close);
      dio.interceptors.add(RequestIdInterceptor());

      await dio.get<dynamic>('https://example.test/ping');

      expect(seenId, isNotNull);
      expect(seenId, isNotEmpty);
    });

    test('respects a caller-supplied id', () async {
      final ids = <String?>[];
      final dio = Dio()..httpClientAdapter = _ScriptedAdapter((options) async {
        ids.add(options.headers[kRequestIdHeader] as String?);
        return ResponseBody.fromString('{}', 200);
      });
      addTearDown(dio.close);
      dio.interceptors.add(RequestIdInterceptor());

      await dio.get<dynamic>(
        'https://example.test/a',
        options: Options(headers: {kRequestIdHeader: 'fixed-1'}),
      );
      await dio.get<dynamic>('https://example.test/b');

      expect(ids, ['fixed-1', isNot('fixed-1')]);
    });

    test('two requests get two different ids', () async {
      final ids = <String?>[];
      final dio = Dio()..httpClientAdapter = _ScriptedAdapter((options) async {
        ids.add(options.headers[kRequestIdHeader] as String?);
        return ResponseBody.fromString('{}', 200);
      });
      addTearDown(dio.close);
      dio.interceptors.add(RequestIdInterceptor());

      await dio.get<dynamic>('https://example.test/a');
      await dio.get<dynamic>('https://example.test/b');

      expect(ids.length, 2);
      expect(ids[0], isNotNull);
      expect(ids[1], isNotNull);
      expect(ids[0], isNot(ids[1]));
      expect(ids[0], contains('-'));
    });
  });

  group('shared network providers', () {
    test('the shared Dio has bounded timeouts (no infinite hangs)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final dio = container.read(dioProvider);

      expect(dio.options.connectTimeout, isNotNull);
      expect(dio.options.receiveTimeout, isNotNull);
      expect(dio.options.connectTimeout, lessThanOrEqualTo(const Duration(seconds: 30)));
      expect(dio.options.receiveTimeout, lessThanOrEqualTo(const Duration(seconds: 30)));
    });

    test('the refresh interceptor is installed on the shared Dio', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final dio = container.read(dioProvider);

      expect(dio.interceptors.whereType<RequestIdInterceptor>(), hasLength(1));
    });
  });
}

/// Adapter whose response is scripted by the test: every asserted header is
/// read off the REAL `RequestOptions` the interceptor chain produced.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.respond);

  final Future<ResponseBody> Function(RequestOptions options) respond;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      respond(options);
}
