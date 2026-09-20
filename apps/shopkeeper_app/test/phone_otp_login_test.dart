import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/core/router/route_names.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/data/auth_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/data/firebase_phone_otp_service.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/domain/auth_methods.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/domain/auth_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/domain/phone_otp.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/screens/login_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/screens/phone_otp_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/screens/welcome_screen.dart';

import 'fakes.dart';

/// Phone-OTP + password sign-in.
///
/// The OTP path converges on the SAME session contract as Google (one Firebase
/// ID-token shape → one `/firebase-login` exchange), so these tests assert both
/// halves: the SMS step owns the code, and the moment it succeeds the
/// controller ends up `authenticated` with the primary shop selected — exactly
/// like `FakeAuthRepository.firebaseLogin`.
void main() {
  ProviderContainer makeContainer(
    FakeAuthRepository repo, {
    PhoneOtpService? otp,
  }) {
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
      phoneOtpServiceProvider.overrideWithValue(
        otp ?? MockPhoneOtpService(delay: Duration.zero),
      ),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  /// The screens navigate with `context.push`, so they need a real router — a
  /// stub destination is enough to prove the navigation happened.
  Future<void> pumpAt(
    WidgetTester tester,
    ProviderContainer container,
    String location,
  ) async {
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(path: Routes.welcome, builder: (_, _) => const WelcomeScreen()),
        GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
        GoRoute(
          path: Routes.phoneOtp,
          builder: (_, _) => const PhoneOtpScreen(),
        ),
        GoRoute(
            path: Routes.register,
            builder: (_, _) => const Scaffold(body: Text('register-screen'))),
        GoRoute(
            path: Routes.forgotPassword,
            builder: (_, _) => const Scaffold(body: Text('forgot-screen'))),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('AuthController.requestPhoneOtp', () {
    test('delegates to the phone provider without touching the auth status',
        () async {
      final otp = MockPhoneOtpService(delay: Duration.zero);
      final container = makeContainer(
        FakeAuthRepository()..restoreResult = makeSession(),
        otp: otp,
      );

      final request = await container
          .read(authControllerProvider.notifier)
          .requestPhoneOtp('+919999999999');

      expect(request.phoneNumber, '+919999999999');
      expect(request.verificationId, isNotNull);
      expect(otp.requestCalls, 1);

      // The router treats `loading` as "the session is unknown" and would swap
      // the OTP screen for the splash — requesting a code must not do that.
      expect(container.read(authControllerProvider).status, AuthStatus.initial);
    });

    test('a resend reuses the pending provider session token', () async {
      final otp = MockPhoneOtpService(delay: Duration.zero);
      final container = makeContainer(FakeAuthRepository(), otp: otp);
      final controller = container.read(authControllerProvider.notifier);

      await controller.requestPhoneOtp('+919999999999');
      await controller.requestPhoneOtp('+919999999999', resendToken: 42);

      expect(otp.requestCalls, 2);
    });
  });

  group('AuthController.verifyPhoneOtp', () {
    test(
        'the correct code authenticates through the SAME /firebase-login '
        'exchange Google uses', () async {
      final fake = FakeAuthRepository()..restoreResult = makeSession();
      final otp = MockPhoneOtpService(delay: Duration.zero);
      final container = makeContainer(fake, otp: otp);

      final request = await container
          .read(authControllerProvider.notifier)
          .requestPhoneOtp('+919999999999');

      final ok = await container
          .read(authControllerProvider.notifier)
          .verifyPhoneOtp(
            verificationId: request.verificationId!,
            code: '123456',
          );

      expect(ok, isTrue);
      expect(otp.verifyCalls, 1);
      // Proof of the no-rewrite guarantee: the OTP token goes through the
      // identical backend exchange, so the session has the same shape.
      expect(fake.firebaseLoginCalls, 1);

      final auth = container.read(authControllerProvider);
      expect(auth.status, AuthStatus.authenticated);
      expect(auth.user, isNotNull);
      expect(container.read(selectedShopProvider), isNotNull);
    });

    test('a wrong code reports why and keeps the shopkeeper signed out',
        () async {
      final container = makeContainer(
        FakeAuthRepository()..restoreResult = makeSession(),
      );

      final request = await container
          .read(authControllerProvider.notifier)
          .requestPhoneOtp('+919999999999');

      final ok = await container
          .read(authControllerProvider.notifier)
          .verifyPhoneOtp(
            verificationId: request.verificationId!,
            code: '000000',
          );

      expect(ok, isFalse);
      final auth = container.read(authControllerProvider);
      expect(auth.status, AuthStatus.error);
      expect(auth.errorMessage, 'The code you entered is incorrect.');
      expect(auth.errorCode, 'invalid-verification-code');
    });

    test('a backend refusal surfaces its own message, not the code error',
        () async {
      final container = makeContainer(
        FakeAuthRepository()
          ..submitError = const ApiException(
            statusCode: 403,
            message: 'This account cannot use phone sign-in.',
          ),
      );

      final request = await container
          .read(authControllerProvider.notifier)
          .requestPhoneOtp('+919999999999');

      final ok = await container
          .read(authControllerProvider.notifier)
          .verifyPhoneOtp(
            verificationId: request.verificationId!,
            code: '123456',
          );

      expect(ok, isFalse);
      expect(
        container.read(authControllerProvider).errorMessage,
        'This account cannot use phone sign-in.',
      );
    });
  });

  group('PhoneOtpScreen', () {
    testWidgets('rejects a number that is not a 10-digit Indian mobile',
        (tester) async {
      final otp = MockPhoneOtpService(delay: Duration.zero);
      final container = makeContainer(FakeAuthRepository(), otp: otp);
      await pumpAt(tester, container, Routes.phoneOtp);

      await tester.enterText(find.byKey(PhoneOtpScreen.phoneFieldKey), '12345');
      await tester.tap(find.byKey(PhoneOtpScreen.sendButtonKey));
      await tester.pumpAndSettle();

      expect(find.byKey(PhoneOtpScreen.errorKey), findsOneWidget);
      expect(find.text('Enter a valid 10-digit mobile number.'), findsOneWidget);
      // Nothing was sent — the provider is never called for a bad number.
      expect(otp.requestCalls, 0);
    });

    testWidgets('a valid number moves to the code step and echoes the number',
        (tester) async {
      final otp = MockPhoneOtpService(delay: Duration.zero);
      final container = makeContainer(FakeAuthRepository(), otp: otp);
      await pumpAt(tester, container, Routes.phoneOtp);

      await tester.enterText(
        find.byKey(PhoneOtpScreen.phoneFieldKey),
        '09999999999', // trunk 0 + 10 digits → +919999999999
      );
      await tester.tap(find.byKey(PhoneOtpScreen.sendButtonKey));
      await tester.pumpAndSettle();

      expect(otp.requestCalls, 1);
      expect(otp.lastRequestedPhone, '+919999999999');
      expect(find.byKey(PhoneOtpScreen.codeFieldKey), findsOneWidget);
      expect(find.textContaining('+919999999999'), findsOneWidget);
    });

    testWidgets('a wrong code keeps the code step and shows the reason',
        (tester) async {
      final container = makeContainer(FakeAuthRepository());
      await pumpAt(tester, container, Routes.phoneOtp);

      await tester.enterText(
          find.byKey(PhoneOtpScreen.phoneFieldKey), '9999999999');
      await tester.tap(find.byKey(PhoneOtpScreen.sendButtonKey));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(PhoneOtpScreen.codeFieldKey), '000000');
      await tester.tap(find.byKey(PhoneOtpScreen.verifyButtonKey));
      await tester.pumpAndSettle();

      expect(find.byKey(PhoneOtpScreen.errorKey), findsOneWidget);
      expect(find.text('The code you entered is incorrect.'), findsOneWidget);
      // Recovery is still possible: the code field was never torn down.
      expect(find.byKey(PhoneOtpScreen.codeFieldKey), findsOneWidget);
    });

    testWidgets('the correct code signs the shopkeeper in', (tester) async {
      final fake = FakeAuthRepository()..restoreResult = makeSession();
      final container = makeContainer(fake);
      await pumpAt(tester, container, Routes.phoneOtp);

      await tester.enterText(
          find.byKey(PhoneOtpScreen.phoneFieldKey), '9999999999');
      await tester.tap(find.byKey(PhoneOtpScreen.sendButtonKey));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(PhoneOtpScreen.codeFieldKey), '123456');
      await tester.tap(find.byKey(PhoneOtpScreen.verifyButtonKey));
      await tester.pumpAndSettle();

      expect(fake.firebaseLoginCalls, 1);
      expect(
        container.read(authControllerProvider).status,
        AuthStatus.authenticated,
      );
    });

    testWidgets('instant verification skips the code step entirely',
        (tester) async {
      final fake = FakeAuthRepository()..restoreResult = makeSession();
      final container = makeContainer(fake, otp: _AutoVerifyingOtpService());
      await pumpAt(tester, container, Routes.phoneOtp);

      await tester.enterText(
          find.byKey(PhoneOtpScreen.phoneFieldKey), '9999999999');
      await tester.tap(find.byKey(PhoneOtpScreen.sendButtonKey));
      await tester.pumpAndSettle();

      // No code field was ever shown, and the sign-in already happened.
      expect(find.byKey(PhoneOtpScreen.codeFieldKey), findsNothing);
      expect(fake.firebaseLoginCalls, 1);
      expect(
        container.read(authControllerProvider).status,
        AuthStatus.authenticated,
      );
    });

    testWidgets('a platform that cannot send SMS explains itself',
        (tester) async {
      final container = makeContainer(
        FakeAuthRepository(),
        otp: _UnsupportedOtpService(),
      );
      await pumpAt(tester, container, Routes.phoneOtp);

      expect(find.byKey(PhoneOtpScreen.unsupportedKey), findsOneWidget);
      expect(find.byKey(PhoneOtpScreen.phoneFieldKey), findsNothing);
      expect(find.text('Phone sign-in unavailable'), findsOneWidget);
    });

    testWidgets('Change number returns to step 1 and keeps the number typed',
        (tester) async {
      final container = makeContainer(FakeAuthRepository());
      await pumpAt(tester, container, Routes.phoneOtp);

      await tester.enterText(
          find.byKey(PhoneOtpScreen.phoneFieldKey), '9999999999');
      await tester.tap(find.byKey(PhoneOtpScreen.sendButtonKey));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(PhoneOtpScreen.codeFieldKey), '1234');
      await tester.tap(find.byKey(PhoneOtpScreen.changeNumberKey));
      await tester.pumpAndSettle();

      expect(find.byKey(PhoneOtpScreen.phoneFieldKey), findsOneWidget);
      expect(find.byKey(PhoneOtpScreen.codeFieldKey), findsNothing);
      // The number is kept in the field, not thrown away.
      final phoneField = tester
          .widget<TextField>(find.byKey(PhoneOtpScreen.phoneFieldKey));
      expect(phoneField.controller?.text, '9999999999');
    });
  });

  group('WelcomeScreen method entry points', () {
    testWidgets('every enabled method gets a visible entry point',
        (tester) async {
      final container = makeContainer(FakeAuthRepository());
      await pumpAt(tester, container, Routes.welcome);

      expect(find.text('Welcome Back'), findsOneWidget);
      expect(find.text(AuthMethod.googleFirebase.actionLabel), findsOneWidget);
      expect(find.byKey(WelcomeScreen.phoneSignInKey), findsOneWidget);
      expect(find.byKey(WelcomeScreen.passwordSignInKey), findsOneWidget);
      expect(find.byKey(WelcomeScreen.createAccountKey), findsOneWidget);
    });

    testWidgets('the phone entry point opens the OTP screen', (tester) async {
      final container = makeContainer(FakeAuthRepository());
      await pumpAt(tester, container, Routes.welcome);

      await tester.tap(find.byKey(WelcomeScreen.phoneSignInKey));
      await tester.pumpAndSettle();

      expect(find.byKey(PhoneOtpScreen.phoneFieldKey), findsOneWidget);
    });

    testWidgets('the password entry point opens the sign-in screen',
        (tester) async {
      final container = makeContainer(FakeAuthRepository());
      await pumpAt(tester, container, Routes.welcome);

      await tester.tap(find.byKey(WelcomeScreen.passwordSignInKey));
      await tester.pumpAndSettle();

      expect(find.byKey(LoginScreen.identifierFieldKey), findsOneWidget);
    });

    testWidgets('narrowing the SSOT list removes the entry points it owns',
        (tester) async {
      final container = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
        phoneOtpServiceProvider.overrideWithValue(
          MockPhoneOtpService(delay: Duration.zero),
        ),
        // A restricted build offers Google only.
        enabledAuthMethodsProvider
            .overrideWithValue(const [AuthMethod.googleFirebase]),
      ]);
      addTearDown(container.dispose);

      await pumpAt(tester, container, Routes.welcome);

      expect(find.text(AuthMethod.googleFirebase.actionLabel), findsOneWidget);
      expect(find.byKey(WelcomeScreen.phoneSignInKey), findsNothing);
      expect(find.byKey(WelcomeScreen.passwordSignInKey), findsNothing);
    });
  });

  group('LoginScreen password sign-in', () {
    testWidgets('an incomplete form is refused before any network call',
        (tester) async {
      final container = makeContainer(FakeAuthRepository());
      await pumpAt(tester, container, Routes.login);

      await tester.tap(find.byKey(LoginScreen.submitKey));
      await tester.pumpAndSettle();

      expect(find.text('Enter your phone number or email'), findsOneWidget);
      expect(find.text('Password is required'), findsOneWidget);
      // Still signed out: nothing was submitted.
      expect(container.read(authControllerProvider).status, AuthStatus.initial);
    });

    testWidgets('a phone number + password signs the shopkeeper in',
        (tester) async {
      final fake = FakeAuthRepository()..restoreResult = makeSession();
      final container = makeContainer(fake);
      await pumpAt(tester, container, Routes.login);

      await tester.enterText(
          find.byKey(LoginScreen.identifierFieldKey), '9999999999');
      await tester.enterText(
          find.byKey(LoginScreen.passwordFieldKey), 'secret123');
      await tester.tap(find.byKey(LoginScreen.submitKey));
      await tester.pumpAndSettle();

      expect(
        container.read(authControllerProvider).status,
        AuthStatus.authenticated,
      );
    });

    testWidgets('a rejected sign-in shows the backend message inline',
        (tester) async {
      final container = makeContainer(
        FakeAuthRepository()
          ..submitError = const ApiException(
            statusCode: 401,
            message: 'Invalid phone number or password.',
          ),
      );
      await pumpAt(tester, container, Routes.login);

      await tester.enterText(
          find.byKey(LoginScreen.identifierFieldKey), 'ramesh@example.com');
      await tester.enterText(
          find.byKey(LoginScreen.passwordFieldKey), 'wrong-password');
      await tester.tap(find.byKey(LoginScreen.submitKey));
      await tester.pumpAndSettle();

      expect(find.byKey(LoginScreen.errorKey), findsOneWidget);
      expect(find.text('Invalid phone number or password.'), findsOneWidget);
    });

    testWidgets('the forgot-password link opens the recovery route',
        (tester) async {
      final container = makeContainer(FakeAuthRepository());
      await pumpAt(tester, container, Routes.login);

      await tester.tap(find.byKey(LoginScreen.forgotKey));
      await tester.pumpAndSettle();

      expect(find.text('forgot-screen'), findsOneWidget);
    });
  });
}

/// Provider that verifies the number without user input (Android instant
/// verification / iOS silent APNs push).
class _AutoVerifyingOtpService implements PhoneOtpService {
  @override
  bool get isSupported => true;

  @override
  Future<PhoneOtpRequest> requestCode(
    String e164PhoneNumber, {
    int? resendToken,
  }) async =>
      PhoneOtpRequest(
        phoneNumber: e164PhoneNumber,
        autoVerifiedIdToken: 'auto-verified-id-token',
      );

  @override
  Future<String> verifyCode({
    required String verificationId,
    required String code,
  }) async =>
      throw StateError('no code step expected');
}

/// Desktop/web build without Phone Auth: the flow must say so, not pretend.
class _UnsupportedOtpService implements PhoneOtpService {
  @override
  bool get isSupported => false;

  @override
  Future<PhoneOtpRequest> requestCode(
    String e164PhoneNumber, {
    int? resendToken,
  }) async =>
      throw const PhoneOtpException('Phone sign-in is not available here.');

  @override
  Future<String> verifyCode({
    required String verificationId,
    required String code,
  }) async =>
      throw const PhoneOtpException('Phone sign-in is not available here.');
}