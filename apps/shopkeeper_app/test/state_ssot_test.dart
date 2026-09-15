import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/data/auth_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/dashboard/data/dashboard_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/data/import_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/notifications/data/notifications_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/notifications/domain/notification_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/notifications/presentation/controllers/notifications_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/data/product_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/data/shop_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/presentation/controllers/shops_controller.dart';

import 'fakes.dart';

ShopkeeperNotification _notification({int id = 1, bool isRead = false}) =>
    ShopkeeperNotification(
      id: id,
      title: 'Low stock: Aashirvaad Atta',
      body: 'Only 3 left in store',
      type: 'INVENTORY_LOW',
      isRead: isRead,
      createdAt: DateTime(2026, 9, 10, 8),
    );

void main() {
  group('SSOT — unread notifications', () {
    test('dashboard alert reads the SAME source as the notifications badge',
        () async {
      final notifications = FakeNotificationsRepo(
        page: NotificationsPage(
          items: [_notification(id: 1), _notification(id: 2)],
          unreadCount: 2,
        ),
      );
      final container = ProviderContainer(overrides: [
        dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepo()),
        notificationsRepositoryProvider.overrideWithValue(notifications),
        // DashboardController._loadAlerts() also derives low-stock alerts from
        // these two repos. Without the overrides they would perform REAL HTTP
        // inside a plain test() (no binding → no HttpOverrides) and hang ~30s.
        inventoryImportRepositoryProvider.overrideWithValue(FakeImportRepo()),
        productRepositoryProvider.overrideWithValue(FakeProductRepo()),
        tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token')),
        selectedShopProvider
            .overrideWith(() => SelectedShopOverride(ownerShop())),
      ]);
      addTearDown(container.dispose);

      // Dashboard load → the alert carries the controller's count.
      await container.read(dashboardControllerProvider.notifier).load();
      expect(
        container.read(dashboardControllerProvider).alerts.unreadNotifications,
        2,
      );

      // Shopkeeper reads everything on the notifications screen (optimistic
      // update lives ONLY in NotificationsController)…
      await container
          .read(notificationsControllerProvider.notifier)
          .markAllAsRead();
      expect(
        container.read(notificationsControllerProvider).unreadCount,
        0,
      );

      // …and the next dashboard load reflects it. No second copy anywhere.
      await container.read(dashboardControllerProvider.notifier).load();
      expect(
        container.read(dashboardControllerProvider).alerts.unreadNotifications,
        0,
      );
      // Exactly one notifications fetch per dashboard load — the dashboard
      // no longer fetches the page itself.
      expect(notifications.fetchCalls, 2);
    });
  });

  group('SSOT — authorized shops', () {
    ProviderContainer makeContainer(FakeAuthRepository authRepo,
        FakeShopRepo shopRepo) {
      final container = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(authRepo),
        shopRepositoryProvider.overrideWithValue(shopRepo),
        tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token')),
      ]);
      addTearDown(container.dispose);
      return container;
    }

    test('a fresh shops refresh mirrors into AuthState (guards never stale)',
        () async {
      final container = makeContainer(
        FakeAuthRepository(restoreResult: makeSession(shops: [ownerShop()])),
        FakeShopRepo(shops: [ownerShop(), managerShop()]),
      );

      // Session restore seeds the snapshot from the backend…
      await container.read(authControllerProvider.notifier).checkSession();
      expect(
        container.read(authControllerProvider).shops.map((s) => s.id),
        [10],
      );

      // …a later refresh (new shop authorized elsewhere) flows through the
      // ONE fetch point (ShopsController) and lands in AuthState too.
      await container.read(shopsControllerProvider.notifier).load();
      expect(
        container.read(authControllerProvider).shops.map((s) => s.id),
        [10, 20],
      );
      // Selection policy (owned by AuthController): current shop still
      // authorized → kept.
      expect(container.read(selectedShopProvider)?.id, 10);
    });

    test('an unauthorized selection is dropped and re-pointed by THE policy',
        () async {
      final container = makeContainer(
        FakeAuthRepository(
            restoreResult: makeSession(shops: [ownerShop(id: 10)])),
        // Backend no longer authorizes shop 10 — only 20 remains.
        FakeShopRepo(shops: [managerShop()]),
      );
      await container.read(authControllerProvider.notifier).checkSession();
      expect(container.read(selectedShopProvider)?.id, 10);

      await container.read(shopsControllerProvider.notifier).load();

      expect(
        container.read(authControllerProvider).shops.map((s) => s.id),
        [20],
      );
      // The stale selection (10) is gone; exactly one shop → auto-selected.
      expect(container.read(selectedShopProvider)?.id, 20);
      // profileComplete (router guard input) reflects the fresh list.
      expect(container.read(authControllerProvider).profileComplete, isTrue);
    });
  });
}
