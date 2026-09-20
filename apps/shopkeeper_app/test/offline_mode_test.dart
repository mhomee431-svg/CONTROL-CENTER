import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/connectivity_service.dart';
import 'package:hyperlocal_shopkeeper_app/core/state/connectivity_controller.dart';
import 'package:hyperlocal_shopkeeper_app/core/state/system_state.dart';
import 'package:hyperlocal_shopkeeper_app/core/theme/app_theme.dart';
import 'package:hyperlocal_shopkeeper_app/core/ui/connectivity_banner.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/data/inventory_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/data/products_snapshot_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/presentation/controllers/products_controller.dart';

/// ConnectivityService double whose link and event stream the test controls.
class _FakeConnectivityService implements ConnectivityService {
  _FakeConnectivityService(this.initialLink);

  TransportLink initialLink;
  final _events = StreamController<ConnectivitySnapshot>.broadcast();

  void emit(TransportLink link) =>
      _events.add(ConnectivitySnapshot(link: link));

  @override
  Future<ConnectivitySnapshot> current() async =>
      ConnectivitySnapshot(link: initialLink);

  @override
  Stream<ConnectivitySnapshot> stream() => _events.stream;
}

/// Backend probe that only answers when the test resolves it, so the
/// "Reconnecting" phase is deterministically observable.
class _GatedProbe {
  final _pending = <Completer<bool>>[];
  int count = 0;

  Future<bool> call() {
    count++;
    final completer = Completer<bool>();
    _pending.add(completer);
    return completer.future;
  }

  void resolveAll(bool value) {
    for (final completer in _pending) {
      completer.complete(value);
    }
    _pending.clear();
  }
}

/// Transport that always fails with Dio's "connection error" — the exact
/// classification `ApiException` maps to `SystemState.offline`.
class _OfflineAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException.connectionError(
      requestOptions: options,
      reason: 'no route to host',
    );
  }
}

/// Transport that answers HTTP 500 — NOT offline, so it must never trigger
/// the snapshot fallback.
class _ServerErrorAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.badResponse,
      response: Response<void>(requestOptions: options, statusCode: 500),
    );
  }
}

const _snapshotForShop1 = <String, dynamic>{
  'items': [
    {
      'id': 11,
      'name': 'Amul Milk 1L',
      'quantity': 5,
      'stock_status': 'LOW_STOCK',
      'is_available': true,
      'is_active': true,
      'price': 27,
    },
  ],
  'summary': {'total': 1, 'active': 1, 'inactive': 0, 'low_stock': 1},
};

Future<void> _settle({int rounds = 8}) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('ConnectivityController (state machine)', () {
    late _FakeConnectivityService link;
    late _GatedProbe probe;
    late ProviderContainer container;

    setUp(() {
      link = _FakeConnectivityService(TransportLink.connected);
      probe = _GatedProbe();
      container = ProviderContainer(overrides: [
        connectivityServiceProvider.overrideWithValue(link),
        // Explicit tear-off (implicit_call_tearoffs lint).
        backendProbeProvider.overrideWithValue(probe.call),
      ]);
      addTearDown(container.dispose);
    });

    test('startup verifies the backend: Reconnecting then Online', () async {
      container.listen(connectivityControllerProvider, (_, _) {});
      await _settle();
      // The optimistic build state is not trusted: the first sync probes the
      // real backend before the app claims to be Online.
      expect(container.read(connectivityControllerProvider).status,
          ConnectivityStatus.reconnecting);
      expect(probe.count, 1);

      probe.resolveAll(true);
      await _settle();
      expect(container.read(connectivityControllerProvider).status,
          ConnectivityStatus.online);
    });

    test('the OS link dropping goes Offline immediately (no probing)',
        () async {
      container.listen(connectivityControllerProvider, (_, _) {});
      await _settle();
      probe.resolveAll(true);
      await _settle();
      expect(container.read(connectivityControllerProvider).isOnline, isTrue);

      link.emit(TransportLink.disconnected);
      await _settle();
      expect(container.read(connectivityControllerProvider).status,
          ConnectivityStatus.offline);
      // A link drop is a fact, not a hypothesis — no probe was spent on it.
      expect(probe.count, 1);
    });

    test('a cold start with no link is Offline without probing', () async {
      link.initialLink = TransportLink.disconnected;
      container.listen(connectivityControllerProvider, (_, _) {});
      await _settle();
      expect(container.read(connectivityControllerProvider).status,
          ConnectivityStatus.offline);
      expect(probe.count, 0);
    });

    test('link return + reachable backend → Reconnecting then Online',
        () async {
      link.initialLink = TransportLink.disconnected;
      container.listen(connectivityControllerProvider, (_, _) {});
      await _settle();
      expect(container.read(connectivityControllerProvider).status,
          ConnectivityStatus.offline);

      link.initialLink = TransportLink.connected;
      link.emit(TransportLink.connected);
      await _settle();
      // Wi-Fi being up is NOT "online" for this app until the backend answers.
      expect(container.read(connectivityControllerProvider).status,
          ConnectivityStatus.reconnecting);

      probe.resolveAll(true);
      await _settle();
      expect(container.read(connectivityControllerProvider).status,
          ConnectivityStatus.online);
    });

    test('link return + unreachable backend falls back to Offline', () async {
      link.initialLink = TransportLink.disconnected;
      container.listen(connectivityControllerProvider, (_, _) {});
      await _settle();

      link.initialLink = TransportLink.connected;
      link.emit(TransportLink.connected);
      await _settle();
      expect(container.read(connectivityControllerProvider).status,
          ConnectivityStatus.reconnecting);

      probe.resolveAll(false);
      await _settle();
      expect(container.read(connectivityControllerProvider).status,
          ConnectivityStatus.offline);
    });

    test('duplicate connected events while Online do not re-probe', () async {
      container.listen(connectivityControllerProvider, (_, _) {});
      await _settle();
      probe.resolveAll(true);
      await _settle();
      expect(container.read(connectivityControllerProvider).isOnline, isTrue);
      final before = probe.count;

      link.emit(TransportLink.connected);
      await _settle();
      link.emit(TransportLink.connected);
      await _settle();

      expect(probe.count, before);
      expect(container.read(connectivityControllerProvider).isOnline, isTrue);
    });

    test('retryNow (the banner button) re-probes and can restore Online',
        () async {
      link.initialLink = TransportLink.disconnected;
      container.listen(connectivityControllerProvider, (_, _) {});
      await _settle();
      expect(container.read(connectivityControllerProvider).status,
          ConnectivityStatus.offline);

      final retrying = container
          .read(connectivityControllerProvider.notifier)
          .retryNow();
      await _settle();
      expect(container.read(connectivityControllerProvider).status,
          ConnectivityStatus.reconnecting);
      probe.resolveAll(true);
      await retrying;
      await _settle();
      expect(container.read(connectivityControllerProvider).isOnline, isTrue);
    });
  });

  group('ConnectivityBanner (widget)', () {
    late _FakeConnectivityService link;
    late _GatedProbe probe;

    Widget harness() => ProviderScope(
          overrides: [
            connectivityServiceProvider.overrideWithValue(link),
            // Explicit tear-off (implicit_call_tearoffs lint).
            backendProbeProvider.overrideWithValue(probe.call),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: ConnectivityBanner()),
          ),
        );

    setUp(() {
      link = _FakeConnectivityService(TransportLink.disconnected);
      probe = _GatedProbe();
    });

    testWidgets('offline copy + retry affordance', (tester) async {
      await tester.pumpWidget(harness());
      await tester.pump();

      expect(
          find.byKey(const Key('connectivity-banner-offline')), findsOneWidget);
      expect(find.textContaining("You're offline"), findsOneWidget);
      expect(find.byKey(const Key('connectivity-banner-retry')),
          findsOneWidget);
    });

    testWidgets('retry re-probes and the banner clears when reachable',
        (tester) async {
      await tester.pumpWidget(harness());
      await tester.pump();

      await tester.tap(find.byKey(const Key('connectivity-banner-retry')));
      await tester.pump();
      probe.resolveAll(true);
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('connectivity-banner-offline')), findsNothing);
    });

    testWidgets('reconnecting shows the probe in flight', (tester) async {
      await tester.pumpWidget(harness());
      await tester.pump();
      // The initial "disconnected" read runs in a microtask; let it land
      // before the link event so the state machine is out of cold start.
      await tester.pump();

      link.initialLink = TransportLink.connected;
      link.emit(TransportLink.connected);
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('connectivity-banner-reconnecting')),
          findsOneWidget);
      expect(find.text('Reconnecting…'), findsOneWidget);
    });

    testWidgets('online renders nothing', (tester) async {
      link.initialLink = TransportLink.connected;
      await tester.pumpWidget(harness());
      await tester.pump();
      probe.resolveAll(true);
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('connectivity-banner-offline')), findsNothing);
      expect(find.byKey(const Key('connectivity-banner-reconnecting')),
          findsNothing);
    });
  });

  group('logout wipes the offline cache', () {
    test('ProductsController.reset clears the snapshot via its repository',
        () async {
      final store = InMemoryProductsSnapshotStore();
      await store.save('1', _snapshotForShop1);
      final container = ProviderContainer(overrides: [
        productsSnapshotStoreProvider.overrideWithValue(store),
        // reset() must reach the store THROUGH the repository that owns it.
        inventoryRepositoryProvider.overrideWithValue(
          ApiInventoryRepository(ApiClient(dio: Dio()), snapshotStore: store),
        ),
      ]);
      addTearDown(container.dispose);

      container.read(productsControllerProvider);
      container.read(productsControllerProvider.notifier).reset();
      await _settle();

      expect(store.clearAllCount, 1);
      expect(await store.read('1'), isNull);
    });
  });

  group('Offline snapshot (products, read-only)', () {
    test('snapshot round-trips through the store', () async {
      final store = InMemoryProductsSnapshotStore();
      await store.save('1', _snapshotForShop1);

      expect(await store.read('1'), _snapshotForShop1);

      await store.clearAll();
      expect(await store.read('1'), isNull);
      expect(store.clearAllCount, 1);
    });

    test('offline fetch WITH a snapshot serves the last synced list', () async {
      final store = InMemoryProductsSnapshotStore();
      await store.save('1', _snapshotForShop1);
      final dio = Dio()..httpClientAdapter = _OfflineAdapter();
      final repo =
          ApiInventoryRepository(ApiClient(dio: dio), snapshotStore: store);

      final overview = await repo.fetchInventoryOverview(1, 'token');

      expect(overview.fromCache, isTrue, reason: 'must be marked as cached');
      expect(overview.items, hasLength(1));
      expect(overview.items.first.name, 'Amul Milk 1L');
      expect(overview.items.first.stockStatus, 'LOW_STOCK');
    });

    test('offline fetch WITHOUT a snapshot surfaces the honest offline error',
        () async {
      final dio = Dio()..httpClientAdapter = _OfflineAdapter();
      final repo = ApiInventoryRepository(ApiClient(dio: dio),
          snapshotStore: InMemoryProductsSnapshotStore());

      await expectLater(
        repo.fetchInventoryOverview(1, 'token'),
        throwsA(isA<ApiException>().having(
            (e) => e.systemState, 'systemState', SystemState.offline)),
      );
    });

    test('server errors never fall back to the snapshot', () async {
      final store = InMemoryProductsSnapshotStore();
      await store.save('1', _snapshotForShop1);
      final dio = Dio()..httpClientAdapter = _ServerErrorAdapter();
      final repo =
          ApiInventoryRepository(ApiClient(dio: dio), snapshotStore: store);

      await expectLater(
        repo.fetchInventoryOverview(1, 'token'),
        throwsA(isA<ApiException>().having((e) => e.systemState,
            'systemState', isNot(SystemState.offline))),
      );
    });

    test('offline writes THROW — they are never reported as saved', () async {
      final store = InMemoryProductsSnapshotStore();
      await store.save('1', _snapshotForShop1);
      final dio = Dio()..httpClientAdapter = _OfflineAdapter();
      final repo =
          ApiInventoryRepository(ApiClient(dio: dio), snapshotStore: store);

      await expectLater(
        repo.adjustStock(1, 11, {'quantity_adjustment': 5}, 'token'),
        throwsA(isA<ApiException>().having(
            (e) => e.systemState, 'systemState', SystemState.offline)),
      );
      // The snapshot still holds the pre-failure truth; no local "success"
      // state was fabricated on top of it.
      expect(await store.read('1'), _snapshotForShop1);
    });
  });
}