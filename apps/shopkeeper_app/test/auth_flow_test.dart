import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/app.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/router/app_router.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/data/auth_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/auth_controller.dart';

import 'fakes.dart';

void main() {
  ProviderContainer makeContainer(FakeAuthRepository repo) =>
      ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(repo),
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
      expect(find.text('Create a business account'), findsOneWidget);

      // A deep link into the protected area bounces back to /welcome.
      container.read(routerProvider).go('/dashboard');
      await tester.pumpAndSettle();
      expect(find.text('Create a business account'), findsOneWidget);
    });
  });
}