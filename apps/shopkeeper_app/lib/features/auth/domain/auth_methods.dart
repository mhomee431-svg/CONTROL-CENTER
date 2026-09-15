import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_models.dart';

/// ── THE "FUTURE APPLY" SWITCH ─────────────────────────────────────────────
///
/// The authentication methods THIS build surfaces in the UI.
///
/// MVP: **Google Sign-In + Firebase Authentication ONLY**. No OTP, no SMS, no
/// password, no custom JWT login is shown to the shopkeeper.
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