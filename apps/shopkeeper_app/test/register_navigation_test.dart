import 'package:flutter/material.dart';
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
          // In-memory secure storage (FlutterSecureStorage has no platform
          // handler in widget tests — its futures never complete otherwise).
          tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token'),
          ),
          // Avoid network calls when the authenticated user is sent to /shops.
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

  testWidgets('register (phone + password) creates account and signs in', (
    tester,
  ) async {
    final fake = FakeAuthRepository();
    final container = makeContainer(fake)..read(authControllerProvider);

    await pumpApp(tester, container);

    // Splash → Welcome (no session).
    expect(find.textContaining('Run your shop'), findsOneWidget);
    expect(fake.registerCalls, 0);

    // Go to register screen.
    container.read(routerProvider).go('/register');
    await tester.pumpAndSettle();
    expect(find.text('Create account'), findsOneWidget);

    // Fill the form.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Your name'),
      'Ramesh Kirana',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Business phone number'),
      '9999999999',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'Password123',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm password'),
      'Password123',
    );
    await tester.pumpAndSettle();

    // Tap "Create account" — this changes auth state (loading → authenticated),
    // which used to recreate the router and bounce back to /welcome.
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    // Must be authenticated and redirected away from the auth screens.
    expect(fake.registerCalls, 1);
    expect(
      container.read(authControllerProvider).status,
      AuthStatus.authenticated,
    );
    expect(find.textContaining('Run your shop'), findsNothing);
    expect(
      container.read(routerProvider).state.matchedLocation,
      anyOf('/shops', '/dashboard', '/shop-register'),
    );
  });

  testWidgets('login (phone + password) lands on shops screen (no bounce)', (
    tester,
  ) async {
    final fake = FakeAuthRepository();
    final container = makeContainer(fake)..read(authControllerProvider);

    await pumpApp(tester, container);

    expect(find.textContaining('Run your shop'), findsOneWidget);

    container.read(routerProvider).go('/login');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Phone number'),
      '9999999999',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'Password123',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    // MUST leave the auth screens — not bounced back to /welcome.
    expect(fake.loginCalls, 1);
    expect(
      container.read(authControllerProvider).status,
      AuthStatus.authenticated,
    );
    expect(find.textContaining('Run your shop'), findsNothing);
    expect(
      container.read(routerProvider).state.matchedLocation,
      anyOf('/shops', '/dashboard', '/shop-register'),
    );
  });

  testWidgets('auth state changes do not reset the router instance', (
    tester,
  ) async {
    final fake = FakeAuthRepository();
    final container = makeContainer(fake)..read(authControllerProvider);

    await pumpApp(tester, container);
    container.read(routerProvider).go('/login');
    await tester.pumpAndSettle();

    final routerBefore = container.read(routerProvider);

    // Trigger auth state changes (loading → authenticated).
    final notifier = container.read(authControllerProvider.notifier);
    await notifier.loginWithPassword('+919000000001', 'Password123');
    await tester.pumpAndSettle();

    // The same router instance must survive — no recreation/reset.
    expect(identical(container.read(routerProvider), routerBefore), isTrue);
    // And we're out of the auth screens, not bounced back to welcome.
    expect(
      container.read(routerProvider).state.matchedLocation,
      anyOf('/shops', '/dashboard', '/shop-register'),
    );
  });
}
