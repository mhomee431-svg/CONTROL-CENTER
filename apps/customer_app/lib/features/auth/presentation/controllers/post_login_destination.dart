import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where to send the customer once sign-in finishes.
///
/// WHY THIS EXISTS
/// ---------------
/// The OTP screen ends with `context.go('/')`, which REPLACES the whole
/// navigation stack. That is correct for a customer who started at the welcome
/// screen — they genuinely have nowhere to go back to.
///
/// It is wrong for a guest who was already using the app. Tapping "Sign in" from
/// Saved, or from a support ticket, and landing on Home afterwards loses the
/// exact page they left: the filters they had set, the product they were
/// reading, the issue they were describing. Sign-in asked them for a phone
/// number; it did not ask them to surrender their place.
///
/// WHY A PROVIDER RATHER THAN A ROUTE PARAMETER
/// --------------------------------------------
/// The destination must survive `pushReplacement('/otp')`, which throws away
/// whatever was passed to the login screen. Carrying it as route data means
/// threading it through every screen in the auth chain and keeping the two in
/// sync. A provider is read at the moment it is needed and cleared the moment
/// it is used, so it cannot go stale or be applied to a later sign-in.
final postLoginDestinationProvider =
    NotifierProvider<PostLoginDestination, String?>(PostLoginDestination.new);

class PostLoginDestination extends Notifier<String?> {
  @override
  String? build() => null;

  /// Records where to return to. Called just before entering the auth flow.
  void set(String location) => state = location;

  /// Returns the destination and clears it in one step.
  String? take() {
    final value = state;
    state = null;
    return value;
  }
}

/// Screens that must never be a post-sign-in destination.
///
/// `/login` would redirect the customer into the screen they just finished, and
/// `/splash` would replay the startup gate — both are loops wearing a
/// destination's clothes.
const Set<String> _neverADestination = {
  '/login',
  '/splash',
  '/otp',
  '/onboarding',
};

/// Records [location] as the post-sign-in destination, if it is worth
/// restoring. Anything that is not a real customer-facing page is ignored, so
/// the caller falls back to Home rather than navigating somewhere meaningless.
void rememberPostLoginDestination(WidgetRef ref, String? location) {
  if (location == null || location.isEmpty) return;
  if (_neverADestination.contains(location)) return;
  ref.read(postLoginDestinationProvider.notifier).set(location);
}
