import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/app.dart';
import 'package:hyperlocal_shopkeeper_app/core/router/app_router.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_providers.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/data/auth_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/data/phone_auth_service.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/auth_controller.dart';

import 'fakes.dart';

/// Regression test for the "Send verification code bounces back" bug.
///
/// Root cause: the router Provider used `ref.watch(authControllerProvider)`,
/// so every auth state change recreated the GoRouter and reset navigation to
/// /splash → /welcome in the middle of the register/login flow.
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

  Future<void> pumpApp(WidgetTester tester, ProviderContainer container) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const ShopkeeperApp(),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('register → send verification code lands on OTP screen', (
      tester) async {
    final fake = FakeAuthRepository();
    final container = makeContainer(fake)..read(authControllerProvider);

    await pumpApp(tester, container);

    // Splash → Welcome (no session).
    expect(find.textContaining('Run your shop'), findsOneWidget);

    // Go to register screen.
    container.read(routerProvider).go('/register');
    await tester.pumpAndSettle();
    expect(find.text('Send verification code'), findsOneWidget);

    // Fill the form.
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Your name'), 'Ramesh Kirana');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Business phone number'),
        '9999999999');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'Password123');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm password'),
        'Password123');
    await tester.pumpAndSettle();

    // Tap "Send verification code" — the exact action that used to bounce
    // back to /welcome because auth state changed (loading → otpSent).
    await tester.tap(find.text('Send verification code'));
    await tester.pumpAndSettle();

    // MUST land on the OTP screen, NOT back at welcome.
    // In REGISTRATION mode the OTP screen greets the new user by name.
    expect(find.text('Verify code'), findsOneWidget);
    expect(find.textContaining('Welcome, Ramesh Kirana'), findsOneWidget);
    expect(find.textContaining('Run your shop'), findsNothing);
  });

  testWidgets('login → send code lands on OTP screen (no bounce)',
      (tester) async {
    final fake = FakeAuthRepository();
    final container = makeContainer(fake)..read(authControllerProvider);

    await pumpApp(tester, container);

    // Splash → Welcome (no session).
    expect(find.textContaining('Run your shop'), findsOneWidget);

    container.read(routerProvider).go('/login');
    await tester.pumpAndSettle();

    // The login screen defaults to Password mode — switch to OTP mode.
    await tester.tap(find.text('OTP'));
    await tester.pumpAndSettle();
    expect(find.text('Send code'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Phone number'), '9999999999');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();

    // MUST land on the OTP screen, NOT back at welcome.
    expect(find.text('Verify code'), findsOneWidget);
    expect(find.textContaining('6-digit code'), findsOneWidget);
    expect(find.textContaining('Run your shop'), findsNothing);
  });

  testWidgets('auth state changes do not reset the router instance',
      (tester) async {
    final fake = FakeAuthRepository();
    final container = makeContainer(fake)..read(authControllerProvider);

    await pumpApp(tester, container);
    container.read(routerProvider).go('/register');
    await tester.pumpAndSettle();

    final routerBefore = container.read(routerProvider);

    // Trigger auth state changes (beginRegistration + sendOtp->otpSent).
    final notifier = container.read(authControllerProvider.notifier);
    notifier.beginRegistration('9999999999', 'Ramesh Kirana');
    await notifier.sendOtp('9999999999');
    await tester.pumpAndSettle();

    // The same router instance must survive — no recreation/reset.
    expect(identical(container.read(routerProvider), routerBefore), isTrue);
    // And we're still on the auth route (register), not bounced to welcome.
    expect(container.read(routerProvider).state.matchedLocation,
        anyOf('/register', '/otp'));
  });
}