import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/app.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/router/app_router.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_providers.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/data/auth_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/data/phone_auth_service.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/auth_controller.dart';

import 'fakes.dart';

void main() {
  ProviderContainer makeContainer(
    FakeAuthRepository repo, {
    PhoneAuthService? phoneAuth,
  }) =>
      ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        phoneAuthServiceProvider.overrideWithValue(
          phoneAuth ?? FakePhoneAuthService(),
        ),
      ]);

  group('registration', () {
    test('sendOtp (Firebase) → submitOtp registers and signs in', () async {
      final repo = FakeAuthRepository();
      final phoneAuth = FakePhoneAuthService();
      final container = makeContainer(repo, phoneAuth: phoneAuth)
        ..read(authControllerProvider);
      final notifier = container.read(authControllerProvider.notifier);

      notifier.beginRegistration('+919000000001', 'Ramesh Kirana');
      final sent = await notifier.sendOtp('+919000000001');

      expect(sent, isTrue);
      expect(container.read(authControllerProvider).status,
          AuthStatus.otpSent);

      final ok = await notifier
          .submitOtp(phoneNumber: '+919000000001', otp: '123456');

      expect(ok, isTrue);
      expect(repo.registerCalls, 1);
      expect(repo.lastRegisteredName, 'Ramesh Kirana');
      expect(repo.loginCalls, 0);
      final state = container.read(authControllerProvider);
      expect(state.status, AuthStatus.authenticated);
    });

    test('duplicate phone surfaces backend conflict message', () async {
      final repo = FakeAuthRepository()
        ..submitError = const ApiException(
            statusCode: 409, message: 'Account already exists.');
      final container = makeContainer(repo)..read(authControllerProvider);
      final notifier = container.read(authControllerProvider.notifier);

      notifier.beginRegistration('+919000000001', 'Dup');
      await notifier.sendOtp('+919000000001');
      final ok = await notifier
          .submitOtp(phoneNumber: '+919000000001', otp: '123456');

      expect(ok, isFalse);
      expect(container.read(authControllerProvider).errorMessage,
          contains('already exists'));
    });

    test('Firebase send failure is surfaced to the user', () async {
      final repo = FakeAuthRepository();
      final phoneAuth = FakePhoneAuthService(shouldFail: true);
      final container = makeContainer(repo, phoneAuth: phoneAuth)
        ..read(authControllerProvider);
      final notifier = container.read(authControllerProvider.notifier);

      final sent = await notifier.sendOtp('+919000000001');

      expect(sent, isFalse);
      expect(container.read(authControllerProvider).status, AuthStatus.error);
    });
  });

  group('login', () {
    test('unknown account shows guidance instead of tokens', () async {
      final repo = FakeAuthRepository()
        ..submitError = const ApiException(
            statusCode: 404, message: 'No account found. Please register first.');
      final container = makeContainer(repo)..read(authControllerProvider);
      final notifier = container.read(authControllerProvider.notifier);

      final ok = await notifier
          .submitOtp(phoneNumber: '+919999999999', otp: '123456');

      expect(ok, isFalse);
      expect(repo.loginCalls, 1);
      expect(container.read(authControllerProvider).status, AuthStatus.error);
      expect(container.read(authControllerProvider).errorMessage,
          contains('register first'));
    });

    test('valid OTP signs in and exposes authorized shops', () async {
      final repo = FakeAuthRepository();
      final container = makeContainer(repo)..read(authControllerProvider);
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
