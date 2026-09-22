import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hyperlocal_shopkeeper_app/core/network/connectivity_service.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/core/state/connectivity_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/domain/auth_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/dashboard/data/dashboard_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/dashboard/domain/dashboard_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/data/inventory_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/data/import_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/notifications/data/notifications_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/shell/app_lifecycle_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/data/shop_repository.dart';

import 'fakes.dart';

/// App-lifecycle contract — background / foreground / reconnect / resume.
///
/// The coordinator must refresh "important stale" data on resume and on
/// network reconnect, SILENTLY (never blanking the screen), and NEVER reload
/// on frames, navigation or short background trips. Every rule below pins one
/// of those behaviors with counted fake repositories and an injectable clock.

/// A signed-in / signed-out auth state without the startup machinery —
/// the lifecycle coordinator only ever reads `isAuthenticated` from it.
class SignedInAuth extends AuthController {
  @override
  AuthState build() => AuthState.authenticated(
        user: const ShopkeeperUser(
          id: 1,
          phoneNumber: '+91 90000 00000',
          name: 'Ramesh',
          role: 'shopkeeper',
        ),
        shops: [ownerShop()],
      );
}

class SignedOutAuth extends AuthController {
  @override
  AuthState build() => AuthState.unauthenticated();
}

/// Counts `listMyShops` (the base fake exposes no counter).
class CountingShopRepo extends FakeShopRepo {
  int listCalls = 0;
  @override
  Future<List<ShopSummary>> listMyShops(String token) async {
    listCalls++;
    return super.listMyShops(token);
  }
}

/// A dashboard fake whose failure can be armed between calls — a failed
/// background refresh must keep the current state, and proving that needs
/// a good load FIRST and a failure SECOND.
class MutableDashboardRepo implements DashboardRepository {
  Object? nextError;
  int calls = 0;
  int? lastShopId;

  @override
  Future<DashboardData> fetchDashboard(int shopId, String token) async {
    calls++;
    lastShopId = shopId;
    if (nextError != null) throw nextError!;
    return DashboardData.fromJson(dashboardJson());
  }
}

/// Scripted connectivity: tests emit the exact transport edges they want.
class ScriptedConnectivity implements ConnectivityService {
  final StreamController<ConnectivitySnapshot> controller =
      StreamController<ConnectivitySnapshot>.broadcast(sync: true);
  TransportLink link = TransportLink.unknown;

  @override
  Future<ConnectivitySnapshot> current() async =>
      ConnectivitySnapshot(link: link);

  @override
  Stream<ConnectivitySnapshot> stream() => controller.stream;

  void emit(TransportLink value) {
    link = value;
    controller.add(ConnectivitySnapshot(link: value));
  }

  void dispose() => controller.close();
}

/// Mutable backend probe — the existing `ConnectivityController` machine
/// only claims ONLINE after a successful probe, so tests decide when
/// "Wi-Fi up" becomes "backend reachable".
class ProbeSwitch {
  bool ok = true;
  Future<bool> call() async => ok;
}

/// Shared fixture state — file-scope so `TestHarness` and `main` share one
/// instance set per test.
late DateTime now;
late ScriptedConnectivity connectivity;
late MutableDashboardRepo dash;
late CountingShopRepo shops;
late ProbeSwitch probe;
late ProviderContainer container;

/// One test's wiring: fake repos, scripted connectivity, injected clock.
class TestHarness {
  void dispose() {
    connectivity.dispose();
    container.dispose();
  }

  /// Lets Riverpod's stream plumbing and the unawaited refresh futures run.
  Future<void> flush() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  AppLifecycleController get coordinator =>
      container.read(appLifecycleControllerProvider.notifier);

  /// Simulates a real drop-and-return: link drops → link returns → the
  /// backend probe answers → the existing `ConnectivityController` machine
  /// settles back on ONLINE (only then does the coordinator treat it as a
  /// reconnect). With [backendOk] false the probe fails and the machine
  /// returns to Offline — "Wi-Fi up" alone is never a reconnect.
  Future<void> reconnect({bool backendOk = true}) async {
    connectivity.emit(TransportLink.disconnected);
    await flush();
    probe.ok = backendOk;
    connectivity.emit(TransportLink.connected);
    for (var i = 0; i < 20; i++) {
      if (container.read(connectivityControllerProvider).isOnline) break;
      await Future<void>.delayed(Duration.zero);
    }
    await flush();
  }

  void background({int minutes = 30}) {
    coordinator.didChangeAppLifecycleState(AppLifecycleState.hidden);
    now = now.add(Duration(minutes: minutes));
    coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestHarness harness({bool signedIn = true, bool withShop = true}) {
    connectivity = ScriptedConnectivity();
    dash = MutableDashboardRepo();
    shops = CountingShopRepo();
    probe = ProbeSwitch();
    now = DateTime(2026, 1, 1, 10);
    container = ProviderContainer(overrides: [
      lifecycleClockProvider.overrideWithValue(() => now),
      connectivityServiceProvider.overrideWithValue(connectivity),
      backendProbeProvider.overrideWithValue(probe.call),
      dashboardRepositoryProvider.overrideWithValue(dash),
      shopRepositoryProvider.overrideWithValue(shops),
      inventoryImportRepositoryProvider.overrideWithValue(FakeImportRepo()),
      inventoryRepositoryProvider
          .overrideWithValue(FakeProductRepo(items: const [])),
      notificationsRepositoryProvider
          .overrideWithValue(FakeNotificationsRepo()),
      tokenStoreProvider.overrideWithValue(
        InMemoryTokenStore(accessToken: 'test-access-token'),
      ),
      authControllerProvider
          .overrideWith(signedIn ? SignedInAuth.new : SignedOutAuth.new),
      if (withShop)
        selectedShopProvider
            .overrideWith(() => SelectedShopOverride(ownerShop())),
    ]);
    // Activates the coordinator: registers the observer and the connectivity
    // watch (which in turn builds the ConnectivityController machine).
    container.read(appLifecycleControllerProvider.notifier);
    return TestHarness();
  }

  group('resume (background → foreground)', () {
    test('a long background refreshes dashboard + shop list exactly once',
        () async {
      final h = harness();
      addTearDown(h.dispose);

      h.background();

      await h.coordinator.refreshIdle;
      expect(dash.calls, 1);
      expect(shops.listCalls, 1);
      expect(
        container.read(dashboardControllerProvider).status,
        DashboardStatus.ready,
      );
    });

    test('a fresh cache is NOT reloaded — short trips cost nothing', () async {
      final h = harness();
      addTearDown(h.dispose);

      h.background(); // first (stale) resume → one refresh
      await h.coordinator.refreshIdle;
      expect(dash.calls, 1);

      // Quick trip inside the staleness window → no network traffic at all.
      h.coordinator.didChangeAppLifecycleState(AppLifecycleState.paused);
      now = now.add(const Duration(minutes: 1));
      h.coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await h.flush();
      expect(dash.calls, 1);
      expect(shops.listCalls, 1);

      // The same state re-delivered (the every-frame guard) → still a no-op.
      h.coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await h.flush();
      expect(dash.calls, 1);

      // Once genuinely stale again → the refresh fires.
      h.coordinator.didChangeAppLifecycleState(AppLifecycleState.paused);
      now = now.add(const Duration(minutes: 10));
      h.coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await h.coordinator.refreshIdle;
      expect(dash.calls, 2);
    });

    test('a signed-out resume refreshes nothing', () async {
      final h = harness(signedIn: false);
      addTearDown(h.dispose);

      h.background();
      await h.flush();

      expect(dash.calls, 0);
      expect(shops.listCalls, 0);
    });

    test('no shop selected → nothing refreshes', () async {
      final h = harness(withShop: false);
      addTearDown(h.dispose);

      h.background();
      await h.flush();

      expect(dash.calls, 0);
      expect(shops.listCalls, 0);
    });

    test('a failed silent refresh keeps the current dashboard visible',
        () async {
      final h = harness();
      addTearDown(h.dispose);

      // Establish a good baseline through the normal load path.
      await container.read(dashboardControllerProvider.notifier).load();
      final before = container.read(dashboardControllerProvider);
      expect(before.status, DashboardStatus.ready);

      dash.nextError = Exception('backend unreachable');
      h.background();
      await h.coordinator.refreshIdle;

      final after = container.read(dashboardControllerProvider);
      expect(after.status, DashboardStatus.ready);
      expect(after.data, same(before.data));
      expect(dash.calls, 2); // load() + the (failed) refresh
    });
  });

  group('network reconnect', () {
    test('a drop that comes back refreshes the important data', () async {
      final h = harness();
      addTearDown(h.dispose);

      await h.reconnect();

      expect(dash.calls, 1);
      expect(shops.listCalls, 1);
    });

    test('Wi-Fi alone is NOT a reconnect — the backend must answer', () async {
      final h = harness();
      addTearDown(h.dispose);

      // Link up, but the probe fails: the machine returns to Offline and the
      // coordinator must NOT treat this as a reconnect.
      await h.reconnect(backendOk: false);
      await h.flush();
      expect(dash.calls, 0);
      expect(shops.listCalls, 0);

                                          // Once the backend actually answers (the banner's Retry) → fires.
      // Make the backend probe succeed: Wi-Fi up alone is NOT a reconnect,
      // but a successful backend answer after Retry triggers the refresh.
      probe.ok = true;
      await container.read(connectivityControllerProvider.notifier).retryNow();
      await h.coordinator.refreshIdle;
      expect(dash.calls, 1);
      expect(shops.listCalls, 1);
    });

    test('a flapping link refreshes at most once per window', () async {
      final h = harness();
      addTearDown(h.dispose);

      await h.reconnect();
      await h.coordinator.refreshIdle;
      expect(dash.calls, 1);

      // Second full cycle inside the throttle window → suppressed.
      now = now.add(const Duration(seconds: 1));
      await h.reconnect();
      await h.flush();
      expect(dash.calls, 1);

      // A later drop that comes back → refreshes again.
      now = now.add(const Duration(seconds: 15));
      await h.reconnect();
      await h.coordinator.refreshIdle;
      expect(dash.calls, 2);
    });

    test('resume and reconnect arriving together refresh ONCE', () async {
      final h = harness();
      addTearDown(h.dispose);

      // The link is down when the app returns from a long background: the
      // resume refresh starts immediately, and the connectivity edge lands
      // on top of it — the in-flight/throttle guards keep it to ONE refresh.
      connectivity.emit(TransportLink.disconnected);
      await h.flush();
      now = now.add(const Duration(minutes: 30));
      h.coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await h.reconnect();
      await h.coordinator.refreshIdle;

      expect(dash.calls, 1);
      expect(shops.listCalls, 1);
    });

    test('reconnect while signed out refreshes nothing', () async {
      final h = harness(signedIn: false);
      addTearDown(h.dispose);

      await h.reconnect();
      await h.flush();

      expect(dash.calls, 0);
      expect(shops.listCalls, 0);
    });
  });
}
