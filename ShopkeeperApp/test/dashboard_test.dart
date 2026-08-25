import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/app.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/data/auth_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/domain/shop_models.dart';

import 'fakes.dart';

void main() {
  group('DashboardController', () {
    test('aggregates operational data for the selected shop', () async {
      final fake = FakeDashboardRepo();
      final container = ProviderContainer(overrides: [
        dashboardRepositoryProvider.overrideWithValue(fake),
        selectedShopProvider.overrideWith(() => SelectedShopOverride(ownerShop())),
      ]);
      addTearDown(container.dispose);

      await container.read(dashboardControllerProvider.notifier).load();

      final state = container.read(dashboardControllerProvider);
      expect(state.status, DashboardStatus.ready);
      expect(fake.lastShopId, 10);

      final data = state.data!;
      // Product counts
      expect(data.products.total, 12);
      expect(data.products.active, 9);
      expect(data.products.inactive, 3);
      // Inventory status
      expect(data.products.inStock, 7);
      expect(data.products.lowStock, 3);
      expect(data.products.outOfStock, 2);
      expect(data.products.totalUnits, 150);
      // Recent updates
      expect(data.recentUpdates, hasLength(2));
      expect(data.recentUpdates.first.label, contains('Basmati Rice'));
      // Offers
      expect(data.offers.total, 3);
      expect(data.offers.active, 1);
      // Verification + subscription status
      expect(data.verification.status, 'PENDING');
      expect(data.verification.isPending, isTrue);
      expect(data.subscription.status, 'NONE');
      expect(data.subscription.hasSubscription, isFalse);
    });

    test('backend 403 becomes a distinct access-denied state', () async {
      final fake = FakeDashboardRepo(
        error: const ApiException(
            statusCode: 403, message: 'You do not have access to this shop.'),
      );
      final container = ProviderContainer(overrides: [
        dashboardRepositoryProvider.overrideWithValue(fake),
        selectedShopProvider.overrideWith(() => SelectedShopOverride(ownerShop())),
      ]);
      addTearDown(container.dispose);

      await container.read(dashboardControllerProvider.notifier).load();

      final state = container.read(dashboardControllerProvider);
      expect(state.status, DashboardStatus.accessDenied);
      expect(state.message, contains('do not have access'));
    });
  });

  group('verification status model', () {
    test('maps lifecycle states correctly', () {
      const verified = VerificationInfo(status: 'VERIFIED');
      const rejected =
          VerificationInfo(status: 'REJECTED', reviewNotes: 'Blurry GST doc');
      const pending = VerificationInfo(status: 'UNDER_REVIEW');

      expect(verified.isVerified, isTrue);
      expect(rejected.isRejected, isTrue);
      expect(pending.isPending, isTrue);
    });
  });

  testWidgets('dashboard renders operational cards for an authorized shop',
      (tester) async {
    final authFake = FakeAuthRepository()..restoreResult = makeSession();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(authFake),
        dashboardRepositoryProvider
            .overrideWithValue(FakeDashboardRepo()),
        selectedShopProvider
            .overrideWith(() => SelectedShopOverride(ownerShop())),
      ]),
      child: const ShopkeeperApp(),
    ));
    addTearDown(container.dispose);
    await tester.pumpAndSettle();

    // Header shows the business name.
    expect(find.text('Kirana Corner'), findsOneWidget);
    // Stat cards
    expect(find.text('Products'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Active products'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(find.text('Inventory status'), findsOneWidget);
    expect(find.text('Out of stock'), findsOneWidget);
    expect(find.text('Offers'), findsOneWidget);
    // Subscription status
    expect(find.text('Subscription'), findsOneWidget);
    expect(find.text('No active plan'), findsOneWidget);
    // Verification banner (unverified shop)
    expect(find.textContaining('not verified yet'), findsOneWidget);
    // Recent updates list
    expect(find.textContaining('Basmati Rice'), findsOneWidget);
  });
}
