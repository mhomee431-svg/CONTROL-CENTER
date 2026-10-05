import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/core/router/route_names.dart';
import 'package:hyperlocal_shopkeeper_app/features/account/presentation/screens/account_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/data/auth_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/data/shop_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/domain/profile_scope.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/presentation/screens/shops_screen.dart';

import 'fakes.dart';

/// CURRENT SINGLE PROFILE OVERRIDE — the app assumes ONE shopkeeper → ONE
/// profile → ONE shop/business, and must not show "Switch Business", "Add
/// Another Shop" or "Manage Multiple Shops" until the future multi-business
/// phase.
///
/// The SSOT is `kMultiShopEnabled = false` in
/// `features/shops/domain/profile_scope.dart`. NOTHING was deleted: the picker
/// screen, its controller, `listMyShops`, the `/shops` route and
/// `SelectedShopNotifier` all stay implemented — this file proves the CURRENT
/// visible flow hides the switcher while the FUTURE seam restores it with the
/// single one-line switch.
void main() {
  ProviderContainer makeContainer(
    FakeAuthRepository authRepo,
    FakeShopRepo shopRepo,
  ) {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepo),
        tokenStoreProvider.overrideWithValue(
          InMemoryTokenStore(accessToken: 'test-access-token'),
        ),
        shopRepositoryProvider.overrideWithValue(shopRepo),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('SSOT — multi-business stays OFF in the MVP', () {
    test('the profile scope switch is single-profile by default', () {
      expect(kMultiShopEnabled, isFalse);
    });

    test('the provider reads the switch (the only thing screens consult)',
        () {
      final container = makeContainer(FakeAuthRepository(), FakeShopRepo());
      expect(container.read(multiShopEnabledProvider), isFalse);
    });

    test('re-enabling the switch is the documented one-line change', () {
      final container = ProviderContainer(
        overrides: [multiShopEnabledProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);
      expect(container.read(multiShopEnabledProvider), isTrue);
    });
  });

  group('Account tab — no business-picker entry in the MVP', () {
    Future<void> pumpAccount(WidgetTester tester) async {
      final container = makeContainer(
        FakeAuthRepository()..restoreResult = makeSession(),
        FakeShopRepo(),
      );
      // Authenticated with the primary shop auto-selected (the real flow).
      await container.read(authControllerProvider.notifier).checkSession();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AccountScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the "My business" picker entry is hidden', (tester) async {
      await pumpAccount(tester);

      // The current business is still shown — but by the read-only
      // `_BusinessCard` ("Current business"), not by an entry that opens the
      // picker.
      expect(find.text('Current business'), findsOneWidget);
      expect(find.text('My business'), findsNothing);
    });

    testWidgets('management still one tap away (Shop profile, Settings)',
        (tester) async {
      await pumpAccount(tester);

      expect(find.text('Shop profile'), findsWidgets);
      expect(find.text('Settings'), findsWidgets);
    });
  });

  group('/shops screen — no select-to-switch in the MVP', () {
    /// The picker route cannot live without a router: `_select` navigates to
    /// the dashboard via `context.go`, so the harness gives it a stub.
    GoRouter stubRouter(ProviderContainer container) {
      final router = GoRouter(
        initialLocation: Routes.shops,
        routes: [
          GoRoute(
            path: Routes.shops,
            builder: (_, _) => const ShopsScreen(),
          ),
          GoRoute(
            path: Routes.dashboard,
            builder: (_, _) => const Scaffold(body: Text('dashboard-screen')),
          ),
        ],
      );
      addTearDown(router.dispose);
      return router;
    }

    Future<ProviderContainer> pumpShops(WidgetTester tester) async {
      final container = makeContainer(
        FakeAuthRepository()..restoreResult = makeSession(),
        FakeShopRepo(),
      );
      await container.read(authControllerProvider.notifier).checkSession();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: stubRouter(container),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('shows the ONE business with no switcher affordance',
        (tester) async {
      final container = await pumpShops(tester);

      expect(find.text('Current business'), findsOneWidget);
      expect(find.text('Kirana Corner'), findsWidgets);
      // The single-shop guarantee: the selection is (and stays) the primary
      // shop — there is nothing on screen to switch between.
      expect(container.read(selectedShopProvider)?.id, 10);
    });

    testWidgets('the picker list-and-select returns with the future switch',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository()
              ..restoreResult = makeSession(
                shops: [ownerShop(id: 10), managerShop(id: 20)],
              ),
          ),
          tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token'),
          ),
          shopRepositoryProvider.overrideWithValue(
            FakeShopRepo(
              shops: [ownerShop(id: 10), managerShop(id: 20)],
            ),
          ),
          multiShopEnabledProvider.overrideWithValue(true),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authControllerProvider.notifier).checkSession();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: stubRouter(container),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The picker is back: both authorized businesses listed…
      expect(find.text('Kirana Corner'), findsWidgets);
      expect(find.text('Branch B'), findsWidgets);
      // …and tapping one selects it (the real switch behaviour: select first,
      // the router moves second).
      await tester.tap(find.text('Branch B'));
      await tester.pump();
      expect(container.read(selectedShopProvider)?.id, 20);
      await tester.pumpAndSettle();
      expect(find.text('dashboard-screen'), findsOneWidget);
    });
  });
}
