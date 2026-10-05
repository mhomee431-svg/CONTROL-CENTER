import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/domain/auth_methods.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/domain/auth_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/screens/login_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/shop_registration/controllers/shop_registration_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/shop_registration/domain/shop_registration_state.dart';
import 'package:hyperlocal_shopkeeper_app/features/shop_registration/presentation/screens/shop_registration_wizard.dart';

/// AUTHENTICATION UI OVERRIDE — OTP stays OUT of the current visible flow.
///
/// Product rule (approved visual reference):
///
///     Current UI:  Continue with Google
///     Future:      Phone OTP
///
/// `kEnabledAuthMethods` — the single chokepoint in `auth_methods.dart` — holds
/// Google only, so every OTP surface must be absent from what the shopkeeper
/// actually sees. The Welcome and Sign-in screens are pinned by
/// `phone_otp_login_test.dart` / `auth_extensibility_test.dart`; THIS file
/// covers the last surface that used to leak OTP — the shop-registration
/// success timeline — and proves the future re-enable is the documented
/// one-line switch and nothing more.
void main() {
  /// Renders the wizard already parked on its final step, so the success
  /// timeline is visible without driving location capture, document uploads and
  /// submit (none of which this rule is about).
  Future<void> pumpSuccessTimeline(
    WidgetTester tester, {
    List<AuthMethod>? enabled,
  }) async {
    final container = ProviderContainer(
      overrides: [
        tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
        shopRegistrationControllerProvider
            .overrideWith(_SuccessStepController.new),
        if (enabled != null)
          enabledAuthMethodsProvider.overrideWithValue(enabled),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ShopRegistrationWizard()),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('MVP — phone OTP is absent from the visible flow', () {
    testWidgets('the registration success timeline shows no OTP row',
        (tester) async {
      await pumpSuccessTimeline(tester);

      expect(find.text('Registration Submitted!'), findsOneWidget);
      // Not built at all: the shopkeeper is never shown a verification stage
      // the app cannot perform while OTP is future scope.
      expect(find.text('OTP Verification'), findsNothing);
    });

    testWidgets('the rest of the verification timeline still renders',
        (tester) async {
      await pumpSuccessTimeline(tester);

      // Hiding ONE row must not hide the section — the stages the backend can
      // still act on stay visible and honest.
      expect(find.text('Verification Timeline'), findsOneWidget);
      expect(find.text('Document Verification'), findsOneWidget);
      expect(find.text('Approval'), findsOneWidget);
    });
  });

  group('Sign-in screen — the password form obeys the same switch', () {
    /// The Sign-in screen is the PASSWORD method's surface. Gating only the
    /// Welcome screen's *link* to it was not enough: the `/sign-in` route stays
    /// registered (so the future re-enable is one line), which means a deep
    /// link could still land on a password form the MVP does not offer.
    Future<void> pumpSignIn(
      WidgetTester tester, {
      List<AuthMethod>? enabled,
    }) async {
      final container = ProviderContainer(
        overrides: [
          tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
          if (enabled != null)
            enabledAuthMethodsProvider.overrideWithValue(enabled),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LoginScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the MVP shows Google only — no password form', (tester) async {
      await pumpSignIn(tester);

      // The current surface is present…
      expect(find.byKey(LoginScreen.googleKey), findsOneWidget);
      // …and the future one is not built at all.
      expect(find.byKey(LoginScreen.passwordFieldKey), findsNothing);
      expect(find.byKey(LoginScreen.identifierFieldKey), findsNothing);
      expect(find.byKey(LoginScreen.submitKey), findsNothing);
      expect(find.byKey(LoginScreen.forgotKey), findsNothing);
      expect(find.text('Password'), findsNothing);
    });

    testWidgets('re-enabling the password method restores the whole form', (
      tester,
    ) async {
      // The seam still works end-to-end: nothing was deleted, so flipping the
      // SSOT brings the identifier field, the password field, Sign in and the
      // Forgot-password link back with no widget edit.
      await pumpSignIn(
        tester,
        enabled: const [AuthMethod.googleFirebase, AuthMethod.password],
      );

      expect(find.byKey(LoginScreen.passwordFieldKey), findsOneWidget);
      expect(find.byKey(LoginScreen.identifierFieldKey), findsOneWidget);
      expect(find.byKey(LoginScreen.submitKey), findsOneWidget);
      expect(find.byKey(LoginScreen.forgotKey), findsOneWidget);
      expect(find.byKey(LoginScreen.googleKey), findsOneWidget);
    });
  });

  group('FUTURE — re-enabling the method is the only change needed', () {
    testWidgets('adding phoneOtp to the SSOT brings the OTP row back',
        (tester) async {
      await pumpSuccessTimeline(
        tester,
        enabled: const [AuthMethod.googleFirebase, AuthMethod.phoneOtp],
      );

      expect(find.text('OTP Verification'), findsOneWidget);
      // And nothing else had to change for it to appear.
      expect(find.text('Verification Timeline'), findsOneWidget);
    });
  });
}

/// Pins the wizard on its final step so the success timeline renders in
/// isolation. `build()` deliberately does NOT call `super` — the base version
/// kicks off category loading and location-listener wiring that this rule has
/// nothing to do with.
class _SuccessStepController extends ShopRegistrationController {
  @override
  ShopRegistrationState build() =>
      const ShopRegistrationState(step: RegistrationStep.success);
}
