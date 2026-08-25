import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/app.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/router/app_router.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/data/auth_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/auth_controller.dart';

import 'fakes.dart';

void main() {
  ProviderContainer makeContainer(FakeAuthRepository fake) =>
      ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(fake),
      ]);

  group('registration', () {
    test('sendOtp → submitOtp creates a business account and signs in',
        () async {
      final fake = FakeAuthRepository();
      final container = makeContainer(fake)..read(authControllerProvider);
      final notifier = container.read(authControllerProvider.notifier);

      notifier.beginRegistration('+919000000001', 'Ramesh Kirana');
      final sent = await notifier.sendOtp('+919000000001');

      expect(sent, isTrue);
      expect(fake.otpSends, 1);
      expect(container.read(authControllerProvider).status,
          AuthStatus.otpSent);

      final ok = await notifier
          .submitOtp(phoneNumber: '+919000000001', otp: '123456');

      expect(ok, isTrue);
      expect(fake.registerCalls, 1);
      expect(fake.lastRegisteredName, 'Ramesh Kirana');
      expect(fake.loginCalls, 0);
      final state = container.read(authControllerProvider);
      expect(state.status, AuthStatus.authenticated);
      expect(state.user?.name, 'Ramesh');
      expect(state.shops.first.membership, 'owner');
    });

    test('duplicate phone surfaces backend conflict message', () async {
      final fake = FakeAuthRepository()
        ..submitError = const ApiException(
            statusCode: 409, message: 'Account already exists.');
      final container = makeContainer(fake)..read(authControllerProvider);
      final notifier = container.read(authControllerProvider.notifier);

      notifier.beginRegistration('+919000000001', 'Dup');
      await notifier.sendOtp('+919000000001');
      final ok = await notifier
          .submitOtp(phoneNumber: '+919000000001', otp: '123456');

      expect(ok, isFalse);
      expect(
          container.read(authControllerProvider).errorMessage,
          contains('already exists'));
    });
  });

  group('login', () {
    test('unknown account shows guidance instead of tokens', () async {
      final fake = FakeAuthRepository()
        ..submitError = const ApiException(
            statusCode: 404, message: 'No account found. Please register first.');
      final container = makeContainer(fake)..read(authControllerProvider);
      final notifier = container.read(authControllerProvider.notifier);

      final ok = await notifier
          .submitOtp(phoneNumber: '+919999999999', otp: '123456');

      expect(ok, isFalse);
      expect(fake.loginCalls, 1);
      expect(container.read(authControllerProvider).status,
          AuthStatus.error);
      expect(container.read(authControllerProvider).errorMessage,
          contains('register first'));
    });

    test('valid OTP signs in and exposes authorized shops', () async {
      final fake = FakeAuthRepository();
      final container = makeContainer(fake)..read(authControllerProvider);
      final ok = await container
          .read(authControllerProvider.notifier)
          .submitOtp(phoneNumber: '+919000000001', otp: '123456');

      expect(ok, isTrue);
      expect(container.read(authControllerProvider).shops, hasLength(1));
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
