import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/router/deep_link_launcher.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../onboarding/presentation/controllers/onboarding_controller.dart';
import 'notifications_controller.dart';
import 'pending_deep_link_controller.dart';

/// Whether the router is past the launch gates and can accept a deep link.
///
/// Mirrors the gate conditions in `routerProvider`'s `redirect`:
///
///  * `AuthStatus.initial` — session not yet restored.
///  * `AuthStatus.loading` — a refresh/verification is in flight.
///  * `onboardingCompleted == null` — the persisted flag is still loading,
///    so every route is redirected to `/splash`.
///  * `onboardingCompleted == false` — the customer has not finished the tour,
///    so the redirect forces everything to `/onboarding`.
///
/// While any of these hold, navigating would be immediately undone by the
/// redirect, which is exactly how a cold-start tap gets lost.
@visibleForTesting
bool isRouterReadyForDeepLink({
  required AuthStatus authStatus,
  required bool? onboardingCompleted,
}) {
  // Still loading, or explicitly not completed — both mean the redirect owns
  // the navigation for now.
  if (onboardingCompleted != true) return false;
  if (authStatus == AuthStatus.initial) return false;
  if (authStatus == AuthStatus.loading) return false;
  return true;
}

/// Replays a queued deep link once — and only once — the app is able to
/// navigate to it.
///
/// Re-runs on every relevant state change (auth, onboarding, the link
/// itself), which is what makes all three FCM entry points land correctly:
///
///  * **terminated** — the link is queued during `initialize()`, long before
///    the gates resolve; this provider is what finally opens it.
///  * **background** — the link is queued on resume and drained on the next
///    frame, after any in-flight token refresh settles.
///  * **in-app banner tap** — the gates are already open, so the drain
///    happens synchronously and the banner still feels instant.
///
/// Uses `go()` rather than `push()`: pushing would leave `/splash` (and
/// possibly `/onboarding`) underneath on the back stack, so a single "back"
/// would return the customer to a screen they never chose. `go()` replaces
/// the stack with the intended destination, which is the correct behaviour
/// for a link that *is* the entry point.
final pendingDeepLinkDrainProvider = Provider<void>((ref) {
  final auth = ref.watch(authControllerProvider);
  final onboarding = ref.watch(onboardingCompletedProvider);
  final link = ref.watch(pendingDeepLinkControllerProvider);

  final ready = isRouterReadyForDeepLink(
    authStatus: auth.status,
    onboardingCompleted: onboarding,
  );
  if (!ready || link == null) return;

  // Wait for the frame so the router has definitely built its navigator:
  // the gates being clear does not guarantee the overlay is mounted yet
  // during the very first post-splash transition.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_drain(ref));
  });
});

Future<void> _drain(Ref ref) async {
  // The provider may have been disposed between the frame callback and here.
  if (!ref.mounted) return;

  // Resolve the navigator BEFORE consuming the link. If it is not mounted
  // yet, the link stays queued and the next gate change retries — consuming
  // it first would risk dropping the customer's tap on the floor.
  final context = rootNavigatorKey.currentContext;
  if (context == null) return;

  final link = ref.read(pendingDeepLinkControllerProvider.notifier).take();
  if (link == null) return;

  // The tap *is* an acknowledgement — mark it read so the badge and the
  // inbox row agree with what the customer just saw. Best-effort: a failure
  // here must never cost us the navigation.
  if (link.notificationId.isNotEmpty) {
    unawaited(
      ref
          .read(notificationsControllerProvider.notifier)
          .markAsRead(link.notificationId),
    );
  }

  try {
    // THROUGH THE LAUNCHER, not straight to `GoRouter.go`.
    //
    // This used to navigate to `link.path` unconditionally, which meant the
    // entire `deep_link_guard` / `deep_link_launcher` subsystem was dead code
    // in production: no existence check, no auth check, no graceful fallback.
    // A notification for a deleted product opened a detail screen whose only
    // possible state was an error-and-retry the customer could never escape.
    //
    // The launcher runs the guard and, on refusal, lands the customer on a real
    // screen with an explanation instead of a dead end. It defaults to `go`,
    // which is the behaviour documented above.
    await ref
        .read(deepLinkLauncherProvider)
        .open(context, link.path);
  } catch (error, stackTrace) {
    debugPrint('Pending deep link navigation failed: $error\n$stackTrace');
  }
}
