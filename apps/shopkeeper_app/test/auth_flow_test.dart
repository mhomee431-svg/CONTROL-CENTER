import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/app.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/core/router/app_router.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/data/auth_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/presentation/controllers/products_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/presentation/controllers/shops_controller.dart';

import 'fakes.dart';

void main() {
  ProviderContainer makeContainer(FakeAuthRepository repo) =>
      ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        // SecureTokenStore uses FlutterSecureStorage, whose platform channel is
        // unavailable in tests — inject the in-memory store so token operations
        // (clearAll / restoreSession) complete synchronously.
        tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
      ]);

  group('Google Sign-In (Firebase)', () {
    test('firebaseLogin creates session and authenticates', () async {
      final repo = FakeAuthRepository();

      final session = await repo.firebaseLogin(
        firebaseIdToken: 'mock-firebase-id-token',
        name: 'Ramesh Kirana',
        email: 'ramesh@example.com',
      );

      expect(repo.firebaseLoginCalls, 1);
      expect(repo.lastRegisteredName, 'Ramesh Kirana');
      expect(session.user.name, 'Ramesh');
      expect(session.shops, hasLength(1));
    });

    test('backend failure surfaces an error message', () async {
      final repo = FakeAuthRepository()
        ..submitError = const ApiException(
            statusCode: 400, message: 'Invalid Firebase token.');

      expect(
        () => repo.firebaseLogin(
          firebaseIdToken: 'bad-token',
          name: 'Test',
        ),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('session handling', () {
    test('checkSession restores profile when authenticated', () async {
      final fake = FakeAuthRepository()..restoreResult = makeSession();
      final container = makeContainer(fake);
      final ok =
          await container.read(authControllerProvider.notifier).checkSession();

      expect(ok, isTrue);
      expect(container.read(authControllerProvider).status,
          AuthStatus.authenticated);
    });

    test('falls back to signed-out without stored tokens', () async {
      final fake = FakeAuthRepository();
      final container = makeContainer(fake);
      final ok =
          await container.read(authControllerProvider.notifier).checkSession();

      expect(ok, isFalse);
      expect(container.read(authControllerProvider).status,
          AuthStatus.unauthenticated);
    });

    testWidgets('signed-out users are kept out of protected routes',
        (tester) async {
      final fake = FakeAuthRepository();
      final container = makeContainer(fake);

      await tester.pumpWidget(
          UncontrolledProviderScope(container: container, child: const ShopkeeperApp()));
      await tester.pumpAndSettle();

      // Splash redirected to Welcome because there is no session.
      expect(find.text('Welcome Back'), findsOneWidget);

      // A deep link into the protected area bounces back to /welcome.
      container.read(routerProvider).go('/dashboard');
      await tester.pumpAndSettle();
      expect(find.text('Welcome Back'), findsOneWidget);
    });
  });

  group('logout (Phase 22)', () {
    test('signs out of Firebase, wipes every cached authenticated state',
        () async {
      final tokens = InMemoryTokenStore(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        sessionId: 'session-1',
      )..setLoggedIn(true);
      final fake = FakeAuthRepository()
        ..restoreResult = makeSession()
        ..tokens = tokens;
      final container = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(fake),
        tokenStoreProvider.overrideWithValue(tokens),
        selectedShopProvider.overrideWith(() => SelectedShopOverride(ownerShop())),
      ]);
      addTearDown(container.dispose);

      // Authenticate first (session restored → shop auto-selected).
      final ok =
          await container.read(authControllerProvider.notifier).checkSession();
      expect(ok, isTrue);
      expect(container.read(authControllerProvider).status,
          AuthStatus.authenticated);
      expect(container.read(selectedShopProvider), isNotNull);

      await container.read(authControllerProvider.notifier).logout();

      // 1) Application authentication state cleared → router returns to
      //    the login screen (unauthenticated redirect).
      final auth = container.read(authControllerProvider);
      expect(auth.status, AuthStatus.unauthenticated);
      expect(auth.user, isNull);
      expect(auth.shops, isEmpty);
      // 2) NO tokens left cached on the device.
      expect(await tokens.readAccessToken(), isNull);
      expect(await tokens.readRefreshToken(), isNull);
      expect(await tokens.readSessionId(), isNull);
      expect(await tokens.isLoggedIn(), isFalse);
      // 3) Shop selection dropped — the next account starts clean.
      expect(container.read(selectedShopProvider), isNull);
      // 4) Backend session revoke attempted exactly once.
      expect(fake.logoutCalls, 1);
      // 5) Feature caches wiped — no previous account's data lingers.
      expect(container.read(dashboardControllerProvider).data, isNull);
      expect(container.read(shopsControllerProvider).shops, isEmpty);
      expect(container.read(productsControllerProvider).items, isEmpty);
    });

    test('logout completes even when the backend revoke fails', () async {
      final tokens = InMemoryTokenStore(accessToken: 'access-token');
      final fake = FakeAuthRepository()
        ..restoreResult = makeSession()
        ..tokens = tokens
        ..logoutError =
            const ApiException(statusCode: 500, message: 'offline');
      final container = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(fake),
        tokenStoreProvider.overrideWithValue(tokens),
        selectedShopProvider.overrideWith(() => SelectedShopOverride(ownerShop())),
      ]);
      addTearDown(container.dispose);

      await container.read(authControllerProvider.notifier).checkSession();
      expect(container.read(authControllerProvider).status,
          AuthStatus.authenticated);

      // Server-side revoke throws → logout must STILL complete locally.
      await container.read(authControllerProvider.notifier).logout();

      expect(container.read(authControllerProvider).status,
          AuthStatus.unauthenticated);
      // Local state reset completed despite the backend failure.
      expect(container.read(selectedShopProvider), isNull);
      expect(await tokens.readAccessToken(), isNull);
      expect(fake.logoutCalls, 1);
    });
  });
}