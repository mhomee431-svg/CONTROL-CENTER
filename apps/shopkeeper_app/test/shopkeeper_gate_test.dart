import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/app.dart';
import 'package:hyperlocal_shopkeeper_app/core/auth/firebase_auth_service.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/data/auth_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/domain/auth_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/screens/account_status_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/dashboard/data/dashboard_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/insights/data/insights_repository.dart';

import 'fakes.dart';

/// NAVIGATION ARCHITECTURE — the SHOPKEEPER access gate.
///
/// Requirement: shopkeeper routes require **Authenticated + SHOPKEEPER
/// access**. A confirmed non-shopkeeper account (e.g. a customer sign-in on
/// the shopkeeper app) must dead-end at the account-status screen.
///
/// The flag is TRI-STATE on purpose: `POST /firebase-login` does not return
/// `is_shopkeeper`, only `GET /auth/me` does. `null` (absent) is resolved as
/// PERMISSIVE so no valid shopkeeper is ever locked out right after login;
/// the authoritative `/auth/me` session refresh settles it afterwards.
ProviderContainer gateContainer({required AuthSession? session}) {
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository()..restoreResult = session,
      ),
      dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepo()),
      insightsRepositoryProvider.overrideWithValue(FakeInsightsRepo()),
      tokenStoreProvider.overrideWithValue(
        InMemoryTokenStore(accessToken: 'test-access-token'),
      ),
      firebaseAuthServiceProvider.overrideWithValue(FakeFirebaseAuthService()),
      selectedShopProvider.overrideWith(
        () => SelectedShopOverride(
          (session == null || session.shops.isEmpty) ? null : session.shops.first,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> pumpGateApp(WidgetTester tester, ProviderContainer container) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const ShopkeeperApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('tri-state parsing (do not collapse to bool)', () {
    test('absent flag stays null (permissive)', () {
      final user = ShopkeeperUser.fromJson({
        'id': 1,
        'phone_number': '+919000000001',
      });
      expect(user.isShopkeeper, isNull);
    });

    test('explicit backend false is preserved', () {
      final user = ShopkeeperUser.fromJson({
        'id': 1,
        'phone_number': '+919000000001',
        'is_shopkeeper': false,
      });
      expect(user.isShopkeeper, isFalse);
    });

    test('explicit backend true is preserved', () {
      final user = ShopkeeperUser.fromJson({
        'id': 1,
        'phone_number': '+919000000001',
        'is_shopkeeper': true,
      });
      expect(user.isShopkeeper, isTrue);
    });
  });

  group('router SHOPKEEPER access gate', () {
    testWidgets('confirmed non-shopkeeper → Account Status dead-end',
        (tester) async {
      await pumpGateApp(
        tester,
        gateContainer(session: makeNonShopkeeperSession()),
      );

      expect(find.byType(AccountStatusScreen), findsOneWidget);
      expect(find.text('Shopkeeper access required'), findsOneWidget);
      // The rest of the app stays unreachable.
      expect(find.byType(DashboardScreen), findsNothing);
    });

    testWidgets('missing flag (login response) stays permissive → Dashboard',
        (tester) async {
      // makeSession() builds a user WITHOUT is_shopkeeper — exactly the
      // firebase-login response shape. No valid shopkeeper may be locked out.
      await pumpGateApp(
        tester,
        gateContainer(session: makeSession()),
      );

      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(find.byType(AccountStatusScreen), findsNothing);
    });

    testWidgets('confirmed shopkeeper → Dashboard', (tester) async {
      await pumpGateApp(
        tester,
        gateContainer(session: makeConfirmedShopkeeperSession()),
      );

      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(find.byType(AccountStatusScreen), findsNothing);
    });
  });
}
