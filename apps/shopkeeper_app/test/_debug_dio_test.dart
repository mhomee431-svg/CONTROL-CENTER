import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';

import 'package:hyperlocal_shopkeeper_app/core/network/token_refresh_interceptor.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';

class A implements HttpClientAdapter {
  final List<int> codes;
  A(this.codes);
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    // ignore: avoid_print
    print('FETCH ${o.uri.path} auth=${o.headers['Authorization']} retried=${o.extra['retried']}');
    return ResponseBody.fromString('{}', codes.removeAt(0), headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }
  @override
  void close({bool force = false}) {}
}

void main() {
  test('debug failing-refresh path', () async {
    final tokens = InMemoryTokenStore(accessToken: 'old-access', refreshToken: 'old-refresh');
    final adapter = A([401]);
    final dio = Dio(BaseOptions(baseUrl: 'https://x.test'))..httpClientAdapter = adapter;
    var expired = 0;
    var refreshCalls = 0;
    final i = TokenRefreshInterceptor(dio: dio, tokenStore: tokens, onSessionExpired: () => expired++, refresher: (_) async { refreshCalls++; return null; });
    dio.interceptors.add(i);
    try {
      await dio.get('/p', options: Options(headers: {'Authorization': 'Bearer old-access'}));
      // ignore: avoid_print
      print('RESOLVED');
    } catch (e) {
      // ignore: avoid_print
      print('THREW ${e.runtimeType}');
    }
    // ignore: avoid_print
    print('refreshCalls=$refreshCalls expired=$expired access=${await tokens.readAccessToken()}');
  });
}
