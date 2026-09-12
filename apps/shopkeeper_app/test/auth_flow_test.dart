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

  group('registration (phone + password)', () {
    test('registerWithPassword creates the account and signs in', () async {
      final repo = FakeAuthRepository();
      final container = makeContainer(repo)..read(authControllerProvider);
      final notifier = container.read(authControllerProvider.notifier);

      final ok = await notifier.registerWithPassword(
        name: 'Ramesh Kirana',
        phoneNumber: '+919000000001',
        password: 'Password123',
      );

      expect(ok, isTrue);
      expect(repo.registerCalls, 1);
      expect(repo.lastRegisteredName, 'Ramesh Kirana');
      final state = container.read(authControllerProvider);
      expect(state.status, AuthStatus.authenticated);
      expect(state.shops, hasLength(1));
    });

    test('duplicate phone surfaces backend conflict message', () async {
      final repo = FakeAuthRepository()
        ..submitError = const ApiException(
            statusCode: 400,
            errorCode: 'PHONE_ALREADY_REGISTERED',
            message: 'Phone number already registered. Please login.');
      final container = makeContainer(repo)..read(authControllerProvider);
      final notifier = container.read(authControllerProvider.notifier);

      final ok = await notifier.registerWithPassword(
        name: 'Dup',
        phoneNumber: '+919000000001',
        password: 'Password123',
      );

      expect(ok, isFalse);
      expect(container.read(authControllerProvider).status, AuthStatus.error);
      expect(container.read(authControllerProvider).errorMessage,
          contains('already registered'));
      expect(container.read(authControllerProvider).errorCode,
          'PHONE_ALREADY_REGISTERED');
    });

    test('backend failure surfaces an error message', () async {
      final repo = FakeAuthRepository()
        ..submitError = const ApiException(
            statusCode: 400, message: 'Invalid phone number.');
      final container = makeContainer(repo)..read(authControllerProvider);
      final notifier = container.read(authControllerProvider.notifier);

      final ok = await notifier.registerWithPassword(
        name: 'Ramesh',
        phoneNumber: '000',
        password: 'Password123',
      );

      expect(ok, isFalse);
      expect(container.read(authControllerProvider).status, AuthStatus.error);
      expect(container.read(authControllerProvider).errorMessage,
          contains('Invalid phone number'));
    });
  });

  group('login (phone + password)', () {
    test('valid credentials sign in and expose authorized shops', () async {
      final repo = FakeAuthRepository();
      final container = makeContainer(repo)..read(authControllerProvider);
      final ok = await container
          .read(authControllerProvider.notifier)
          .loginWithPassword('+919000000001', 'Password123');

      expect(ok, isTrue);
      expect(repo.loginCalls, 1);
      expect(container.read(authControllerProvider).status,
          AuthStatus.authenticated);
      expect(container.read(authControllerProvider).shops, hasLength(1));
    });

    test('invalid credentials surface the backend message', () async {
      final repo = FakeAuthRepository()
        ..submitError = const ApiException(
            statusCode: 401, message: 'Invalid credentials');
      final container = makeContainer(repo)..read(authControllerProvider);
      final notifier = container.read(authControllerProvider.notifier);

      final ok =
          await notifier.loginWithPassword('+919000000001', 'wrong-password');

      expect(ok, isFalse);
      expect(container.read(authControllerProvider).status, AuthStatus.error);
      expect(container.read(authControllerProvider).errorMessage,
          contains('Invalid credentials'));
    });
  });

  group('session handling', () {
    test('restores a persisted session on startup', () async {
      final fake = FakeAuthRepository()..restoreResult = makeSession();
      final container = makeContainer(fake)..read(authControllerProvider);
      final ok =
          await container.read(authControllerProvider.notifier).checkSession();

      expect(ok, isTrue);
      expect(container.read(authControllerProvider).status,
          AuthStatus.authenticated);
    });

    test('falls back to signed-out without stored tokens', () async {
      final fake = FakeAuthRepository();
      final container = makeContainer(fake)..read(authControllerProvider);
      final ok =
          await container.read(authControllerProvider.notifier).checkSession();

      expect(ok, isFalse);
      expect(container.read(authControllerProvider).status,
          AuthStatus.unauthenticated);
    });

    testWidgets('signed-out users are kept out of protected routes',
        (tester) async {
      final fake = FakeAuthRepository(); // nothing persisted → signed out
      final container = makeContainer(fake)..read(authControllerProvider);

      await tester.pumpWidget(
          UncontrolledProviderScope(container: container, child: const ShopkeeperApp()));
      await tester.pumpAndSettle();

      // Splash redirected to Welcome because there is no session.
      expect(find.textContaining('Run your shop'), findsOneWidget);

      // A deep link into the protected area bounces back to /welcome.
      container.read(routerProvider).go('/dashboard');
      await tester.pumpAndSettle();
      expect(find.textContaining('Run your shop'), findsOneWidget);
    });
  });
}