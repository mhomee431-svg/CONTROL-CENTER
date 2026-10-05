import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_providers.dart';
import 'package:hyperlocal_shopkeeper_app/features/shell/capabilities_controller.dart';

/// CAPABILITIES — the single entitlement gate. Two failure modes matter, and
/// both are about WHICH answer ends up in `state`, not about whether the
/// request succeeds:
///
///  1. Duplicate in-flight reads (resume / reconnect / pull-to-refresh can all
///     overlap), which are identical `GET .../capabilities` round trips.
///  2. A STALE write: switch shops while a read is resolving and the older
///     shop's answer can land last, gating the wrong shop with the wrong plan.
void main() {
  late List<Map<String, dynamic>> requests;

  late _RecordingApiClient client;

  /// Overrides the API client with one that records each call and waits on a
  /// gate, so a test controls exactly when each read resolves.
  ProviderContainer gatedClient() {
    requests = [];
    client = _RecordingApiClient(requests);
    final c = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(client)],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// Overrides the API client with one that answers immediately.
  ProviderContainer immediateClient() {
    requests = [];
    client = _RecordingApiClient(requests);
    final c = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(client)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('concurrent loads for the same shop make ONE request', () async {
    final c = gatedClient();
    final notifier = c.read(capabilitiesControllerProvider.notifier);

    // Three callers (resume, reconnect, pull-to-refresh) fire before any
    // response lands — exactly what the shell does on a busy app switch.
    client.hold();
    final a = notifier.load(10, 'tok');
    final b = notifier.load(10, 'tok');
    final d = notifier.load(10, 'tok');
    await Future<void>.delayed(Duration.zero);
    expect(requests.length, 1, reason: 'a pending read answers this already');

    client.release(canCreateOffers: false);
    await Future.wait([a, b, d]);
    expect(c.read(capabilitiesControllerProvider).canCreateOffers, isFalse);
  });

  test('a read for a DIFFERENT shop is not dropped', () async {
    final c = immediateClient();
    final notifier = c.read(capabilitiesControllerProvider.notifier);

    // The dedup keys on the shop id precisely so switching shops still works.
    await notifier.load(10, 'tok');
    await notifier.load(11, 'tok');

    expect(requests.length, 2, reason: 'two shops are two different reads');
  });

  test('a stale read cannot overwrite the newly selected shop', () async {
    final c = gatedClient();
    final notifier = c.read(capabilitiesControllerProvider.notifier);

    // Shop 10 read starts, and the user switches to shop 11 before it returns.
    client.hold();
    final stale = notifier.load(10, 'tok');
    await Future<void>.delayed(Duration.zero);

    // Let the shop-11 read complete first, so it is the newest answer.
    final fresh = notifier.load(11, 'tok');
    client.release(canCreateOffers: false);
    await fresh;
    expect(c.read(capabilitiesControllerProvider).canCreateOffers, isFalse);

    // Now the OLD request finally returns, carrying the opposite plan.
    client.hold();
    client.release(canCreateOffers: true);
    await stale;

    // Shop 11's answer must stand: the late reply from shop 10 is stale.
    expect(
      c.read(capabilitiesControllerProvider).canCreateOffers,
      isFalse,
      reason: 'the older shop read must not gate the shop now selected',
    );
  });

  test('logout clears the in-flight read so it cannot leak flags', () async {
    final c = gatedClient();
    final notifier = c.read(capabilitiesControllerProvider.notifier);

    // Establish a NON-default state first, so the assertion below cannot pass
    // merely because `reset()` restores the permissive default (which is
    // `true`). Without this the test would prove nothing.
    client.hold();
    final first = notifier.load(10, 'tok');
    client.release(canCreateOffers: false);
    await first;
    expect(
      c.read(capabilitiesControllerProvider).canCreateOffers,
      isFalse,
      reason: 'precondition: a denied flag must be in state before reset()',
    );

    // A second read is left pending, then the user signs out.
    client.hold();
    final pending = notifier.load(10, 'tok');
    await Future<void>.delayed(Duration.zero);
    notifier.reset();

    // It resolves AFTER logout, carrying the now-stale answer. `reset()`
    // restores the permissive default, so the flag must read `true`; if the
    // in-flight write still landed it would read `false`.
    client.release(canCreateOffers: false);
    await pending;

    expect(
      c.read(capabilitiesControllerProvider).canCreateOffers,
      isTrue,
      reason: 'a signed-out session must not inherit the previous flags',
    );
  });
}

/// The backend serialises these flags in camelCase — confirmed against both
/// `packages/api_contracts/openapi.json` and `entitlements.py`. Using the wrong
/// case here is not a typo risk: `ShopCapabilities.fromJson` defaults every
/// missing flag to `true` (permissive), so a mis-cased fixture silently reads
/// as "fully entitled" and the test would pass for the wrong reason.
Map<String, dynamic> _flags({required bool canCreateOffers}) => {
      'canCreateOffers': canCreateOffers,
      'canUsePos': canCreateOffers,
      'canUploadExcel': canCreateOffers,
      'canViewReports': canCreateOffers,
    };

/// Records every call and, when [gate] is set, waits on it so a test decides
/// exactly when each request resolves — that is what makes an out-of-order
/// completion reproducible instead of a race that only shows up on a slow day.
class _RecordingApiClient implements ApiClient {
  _RecordingApiClient(this.calls);

  final List<Map<String, dynamic>> calls;
  Completer<Map<String, dynamic>>? _pending;

  /// Makes the NEXT request hang until [release]. Lets a test decide exactly
  /// when each read resolves, which is what turns an out-of-order completion
  /// from a flaky race into something reproducible.
  void hold() => _pending = Completer<Map<String, dynamic>>();

  void release({required bool canCreateOffers}) {
    final p = _pending;
    _pending = null;
    p?.complete(_flags(canCreateOffers: canCreateOffers));
  }

  @override
  Dio get dio => throw UnimplementedError('not used by this controller');

  @override
  void Function(ApiException error)? get onUnauthorized => null;

  @override
  Future<dynamic> get(String path,
      {Map<String, dynamic>? query, String? token}) async {
    calls.add({'path': path, 'token': token});
    final p = _pending;
    if (p == null) return _flags(canCreateOffers: calls.length.isOdd);
    return p.future;
  }

  @override
  Future<dynamic> post(String path, {Object? body, String? token}) async =>
      throw UnimplementedError('not used');

  @override
  Future<dynamic> patch(String path, {Object? body, String? token}) async =>
      throw UnimplementedError('not used');

  @override
  Future<dynamic> put(String path, {Object? body, String? token}) async =>
      throw UnimplementedError('not used');

  @override
  Future<dynamic> delete(String path, {String? token}) async =>
      throw UnimplementedError('not used');

  @override
  Future<dynamic> postMultipart(
    String path, {
    required FormData form,
    String? token,
  }) async =>
      throw UnimplementedError('not used');

  @override
  Future<void> postFormToExternal(String url, {required FormData form}) async =>
      throw UnimplementedError('not used');
}
