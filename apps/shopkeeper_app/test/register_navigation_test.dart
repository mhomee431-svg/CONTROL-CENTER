import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/app.dart';
import 'package:hyperlocal_shopkeeper_app/core/router/app_router.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/data/auth_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/data/shop_repository.dart';

import 'fakes.dart';

/// Regression test for the "auth state change bounces back to /welcome" bug.
///
/// Root cause: the router Provider used `ref.watch(authControllerProvider)`,
/// so every auth state change recreated the GoRouter and reset navigation to
/// /splash → /welcome in the middle of the register/login flow.
void main() {
  ProviderContainer makeContainer(FakeAuthRepository repo) => ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(repo),
          tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token'),
          ),
          shopRepositoryProvider.overrideWithValue(FakeShopRepo()),
        ],
      );

  Future<void> pumpApp(WidgetTester tester, ProviderContainer container) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ShopkeeperApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Google Sign-In creates session and signs in', (tester) async {
    final fake = FakeAuthRepository();
    final container = makeContainer(fake)..read(authControllerProvider);

    await pumpApp(tester, container);

    // Splash -> Welcome (no session). The redesigned Google-only welcome
    // screen shows the "Welcome Back" headline with the Google CTA.
    expect(find.text('Welcome Back'), findsOneWidget);
    expect(fake.firebaseLoginCalls, 0);

    // Simulate successful Firebase Google Sign-In via repository.
    await fake.firebaseLogin(
      firebaseIdToken: 'mock-firebase-token',
      name: 'Ramesh Kirana',
      email: 'ramesh@example.com',
    );
    expect(fake.firebaseLoginCalls, 1);
    expect(fake.lastRegisteredName, 'Ramesh Kirana');

    // Check session should restore the authenticated state.
    await container.read(authControllerProvider.notifier).checkSession();
    await tester.pumpAndSettle();

    // Must be authenticated.
    expect(
      container.read(authControllerProvider).status,
      AuthStatus.authenticated,
    );
  });

  testWidgets('auth state changes do not reset the router instance',
      (tester) async {
    final fake = FakeAuthRepository();
    final container = makeContainer(fake)..read(authControllerProvider);

    await pumpApp(tester, container);

    final routerBefore = container.read(routerProvider);

    // Trigger auth state changes (loading -> authenticated).
    await fake.firebaseLogin(
      firebaseIdToken: 'mock-firebase-token',
      name: 'Test Shopkeeper',
    );
    await container.read(authControllerProvider.notifier).checkSession();
    await tester.pumpAndSettle();

    // The same router instance must survive -- no recreation/reset.
    expect(identical(container.read(routerProvider), routerBefore), isTrue);
  });
}