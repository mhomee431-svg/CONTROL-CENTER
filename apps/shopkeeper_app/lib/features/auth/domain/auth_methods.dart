import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_models.dart';

/// ── THE "FUTURE APPLY" SWITCH ─────────────────────────────────────────────
///
/// The authentication methods THIS build surfaces in the UI.
///
/// MVP: **Google Sign-In + Firebase Authentication** is the primary method;
/// Phone OTP and password login are enabled below and reachable from the
/// Welcome / Sign-in screens. Every screen consults
/// [isAuthMethodEnabledProvider] instead of hardcoding a button, so removing a
/// method from this list removes its entry points without deleting the flow.
///
/// Adding Phone OTP later is deliberately a ONE-LINE change here:
///
/// ```dart
/// const List<AuthMethod> kEnabledAuthMethods = [
///   AuthMethod.googleFirebase,
///   AuthMethod.phoneOtp, // ← future
/// ];
/// ```
///
/// …plus registering a real PhoneOtpService. The OTP screen, the controller
/// methods, the repository contract, the session models and the token storage
/// already exist and are already tested, so nothing is rewritten — the UI
/// simply becomes visible.
const List<AuthMethod> kEnabledAuthMethods = <AuthMethod>[
  AuthMethod.googleFirebase,
  AuthMethod.phoneOtp,
  AuthMethod.password,
];

/// Runtime list of the enabled auth methods.
///
/// Screens `watch` this provider (or [isAuthMethodEnabledProvider]) instead of
/// branching on a compile-time constant, so the visible method set can be
/// changed by a future build flag — or overridden in a test — without touching
/// any widget.
final enabledAuthMethodsProvider = Provider<List<AuthMethod>>(
  (ref) => kEnabledAuthMethods,
);

/// True when the UI must offer [method].
final isAuthMethodEnabledProvider = Provider.family<bool, AuthMethod>(
  (ref, method) => ref.watch(enabledAuthMethodsProvider).contains(method),
);

/// Shopkeeper-facing label for a method's primary action.
///
/// Shared by the Welcome screen and the Sign-in screen so the same method can
/// never be labelled two different ways in two places.
extension AuthMethodActionLabel on AuthMethod {
  String get actionLabel => switch (this) {
        AuthMethod.googleFirebase => 'Continue with Google',
        AuthMethod.phoneOtp => 'Continue with phone number',
        AuthMethod.password => 'Sign in with password',
      };
}