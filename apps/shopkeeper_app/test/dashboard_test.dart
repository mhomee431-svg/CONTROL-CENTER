import 'dart:ui' show Size;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/app.dart';
import 'package:hyperlocal_shopkeeper_app/core/auth/firebase_auth_service.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/data/auth_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/dashboard/data/dashboard_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/domain/shop_models.dart';

import 'fakes.dart';

/// Mirrors the dashboard's time-based greeting (dashboard_screen.dart) so
/// these assertions are stable no matter what hour the suite runs.
String expectedGreeting(String name) {
  final hour = DateTime.now().hour;
  final part = hour < 12
      ? 'Good Morning'
      : hour < 17
          ? 'Good Afternoon'
          : 'Good Evening';
  return '$part, $name';
}

void main() {
  group('DashboardController', () {
    test('aggregates operational data for the selected shop', () async {
      final fake = FakeDashboardRepo();
      final container = ProviderContainer(overrides: [
        dashboardRepositoryProvider.overrideWithValue(fake),
        tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token')),
        selectedShopProvider.overrideWith(() => SelectedShopOverride(ownerShop())),
      ]);
      addTearDown(container.dispose);

      await container.read(dashboardControllerProvider.notifier).load();

      final state = container.read(dashboardControllerProvider);
      expect(state.status, DashboardStatus.ready);
      expect(fake.lastShopId, 10);

      final data = state.data!;
      expect(data.products.total, 12);
      expect(data.products.active, 9);
      expect(data.products.inactive, 3);
      expect(data.products.inStock, 7);
      expect(data.products.lowStock, 3);
      expect(data.products.outOfStock, 2);
      expect(data.products.totalUnits, 150);
      expect(data.recentUpdates, hasLength(2));
      expect(data.recentUpdates.first.label, contains('Basmati Rice'));
      expect(data.offers.total, 3);
      expect(data.offers.active, 1);
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
        tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token')),
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
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(authFake),
      dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepo()),
      tokenStoreProvider.overrideWithValue(
          InMemoryTokenStore(accessToken: 'test-access-token')),
      selectedShopProvider.overrideWith(() => SelectedShopOverride(ownerShop())),
    ]);
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const ShopkeeperApp(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Kirana Corner'), findsOneWidget);
    expect(find.textContaining('Ramesh'), findsOneWidget);
    expect(find.text('Shop: Kirana Corner'), findsOneWidget);
    expect(find.text('Profile Status: Profile Created'), findsOneWidget);
    expect(find.text('Products'), findsWidgets);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Active products'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(find.text('Inventory status'), findsOneWidget);
    expect(find.text('Out of stock'), findsOneWidget);
    expect(find.text('Offers'), findsOneWidget);
    expect(find.text('Subscription'), findsOneWidget);
    expect(find.text('No active plan'), findsOneWidget);
    expect(find.textContaining('not verified yet'), findsOneWidget);
    expect(find.textContaining('Basmati Rice'), findsOneWidget);
    expect(find.text('Quick Actions'), findsOneWidget);
    expect(find.text('Add Product'), findsOneWidget);
    expect(find.text('Inventory'), findsOneWidget);
    expect(find.text('Pricing & Offers'), findsOneWidget);
    expect(find.text('Reports & Insights'), findsOneWidget);
    expect(find.text('All Features'), findsOneWidget);
    expect(find.text('Shop Profile'), findsOneWidget);
  });

  group('app startup (Phase 23)', () {
    testWidgets('active profile with a shop -> Shopkeeper Home',
        (tester) async {
      final authFake = FakeAuthRepository()..restoreResult = makeSession();
      final container = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(authFake),
        dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepo()),
        tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token')),
        selectedShopProvider.overrideWith(() => SelectedShopOverride(ownerShop())),
      ]);
      addTearDown(container.dispose);
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const ShopkeeperApp(),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Kirana Corner'), findsOneWidget);
      expect(find.text(expectedGreeting('Ramesh')), findsOneWidget);
    });

    testWidgets('active profile WITHOUT a shop -> Create Profile',
        (tester) async {
      final authFake =
          FakeAuthRepository()..restoreResult = makeEmptyProfileSession();
      final container = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(authFake),
        tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token')),
        selectedShopProvider.overrideWith(() => SelectedShopOverride(null)),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const ShopkeeperApp(),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Create Your Shopkeeper Profile'), findsOneWidget);
    });

    testWidgets('suspended account -> account-status gate',
        (tester) async {
      final authFake =
          FakeAuthRepository()..restoreResult = makeRestrictedSession();
      final container = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(authFake),
        tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token')),
        selectedShopProvider.overrideWith(() => SelectedShopOverride(ownerShop())),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const ShopkeeperApp(),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Account Suspended'), findsOneWidget);
      expect(
          find.textContaining('suspended. Please contact support'),
          findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      expect(find.text('Kirana Corner'), findsNothing);
    });

    testWidgets('account-status sign-out -> returns to Welcome',
        (tester) async {
      final authFake =
          FakeAuthRepository()..restoreResult = makeRestrictedSession();
      final container = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(authFake),
        tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token')),
        // Real FirebaseAuthService.signOut() hangs on the test VM's platform
        // channel — inject a no-op fake so the logout flow completes.
        firebaseAuthServiceProvider.overrideWithValue(FakeFirebaseAuthService()),
        selectedShopProvider.overrideWith(() => SelectedShopOverride(ownerShop())),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const ShopkeeperApp(),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Account Suspended'), findsOneWidget);
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome Back'), findsOneWidget);
      expect(container.read(authControllerProvider).status,
          AuthStatus.unauthenticated);
    });
  });

  // Phase 24: account status (ACTIVE / INACTIVE / SUSPENDED) is separate from
  // any future merchant-verification state machine.
  group('account status (Phase 24)', () {
    testWidgets('INACTIVE account -> account-status gate with inactive copy',
        (tester) async {
      final authFake = FakeAuthRepository()
        ..restoreResult = makeRestrictedSession(status: 'INACTIVE');
      final container = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(authFake),
        tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token')),
        firebaseAuthServiceProvider.overrideWithValue(FakeFirebaseAuthService()),
        selectedShopProvider.overrideWith(() => SelectedShopOverride(ownerShop())),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const ShopkeeperApp(),
      ));
      await tester.pumpAndSettle();

      // INACTIVE -> account-status screen (NOT the app, NOT verification).
      expect(find.text('Account Not Active'), findsOneWidget);
      expect(find.textContaining('inactive. Please contact support'),
          findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      // The dashboard (Shopkeeper Home) must NOT be reachable.
      expect(find.text('Kirana Corner'), findsNothing);
    });

    testWidgets('BANNED account -> account-status gate with banned copy',
        (tester) async {
      final authFake = FakeAuthRepository()
        ..restoreResult = makeRestrictedSession(status: 'BANNED');
      final container = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(authFake),
        tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token')),
        firebaseAuthServiceProvider.overrideWithValue(FakeFirebaseAuthService()),
        selectedShopProvider.overrideWith(() => SelectedShopOverride(ownerShop())),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const ShopkeeperApp(),
      ));
      await tester.pumpAndSettle();

      // BANNED -> account-status screen with banned copy.
      expect(find.text('Account Suspended'), findsOneWidget);
      expect(find.textContaining('banned. Please contact support'),
          findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      expect(find.text('Kirana Corner'), findsNothing);
    });

    testWidgets('ACTIVE account -> normal app (no status gate)',
        (tester) async {
      final authFake = FakeAuthRepository()..restoreResult = makeSession();
      final container = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(authFake),
        dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepo()),
        tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token')),
        selectedShopProvider.overrideWith(() => SelectedShopOverride(ownerShop())),
      ]);
      addTearDown(container.dispose);
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const ShopkeeperApp(),
      ));
      await tester.pumpAndSettle();

      // ACTIVE -> normal app, no account-status gate.
      expect(find.text('Kirana Corner'), findsOneWidget);
      expect(find.text(expectedGreeting('Ramesh')), findsOneWidget);
      expect(find.text('Account Suspended'), findsNothing);
      expect(find.text('Account Not Active'), findsNothing);
    });
  });
}