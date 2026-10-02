import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/controllers/auth_controller.dart';
import 'deep_link.dart';

/// Why a deep link was not opened.
///
/// Ordered to match the sequence in [evaluateDeepLink], so a reader can follow
/// the checks top-to-bottom.
enum DeepLinkBlockReason {
  /// The link could not be parsed into a known entity, or its id/query is
  /// missing or unsafe. Nothing was ever requested.
  malformed,

  /// The app is not in a state that can act on a link yet (session still
  /// resolving, onboarding not finished).
  missingContext,

  /// The entity exists but this customer may not open it -- typically the
  /// link targets account-scoped content while signed out or browsing as a
  /// guest.
  unauthenticated,

  /// The entity is gone: deleted, or never existed. A well-formed link to a
  /// product the shopkeeper removed.
  notFound,

  /// The entity exists but cannot be shown right now (expired offer, product
  /// with no sellable stock left).
  unavailable,
}

/// What a probe learned about the entity a link points at.
enum DeepLinkTargetState {
  /// Exists and can be shown.
  available,

  /// Does not exist any more.
  gone,

  /// Exists but is not openable.
  unavailable,
}

/// The app-side facts a decision depends on.
///
/// Passing these in (rather than reading providers inside the guard) is what
/// makes the policy a pure function: every branch below is reachable from a
/// test with no container, no network and no clock.
class DeepLinkEnvironment {
  /// Current auth status, used for the account-scoped check.
  final AuthStatus authStatus;

  /// Whether the launch gates are clear enough to navigate.
  final bool isAppReady;

  /// Injected so expiry decisions are deterministic under test.
  final DateTime now;

  const DeepLinkEnvironment({
    required this.authStatus,
    required this.isAppReady,
    required this.now,
  });
}

/// The outcome of validating a link.
class DeepLinkDecision {
  /// True when [path] is safe to navigate to.
  final bool isAllowed;

  /// Where the customer should go. Set when [isAllowed].
  final String? path;

  /// Where the customer lands when the link is refused. Always set, and always
  /// a route that itself needs no validation.
  final String fallbackPath;

  /// Why the link was refused; null when allowed.
  final DeepLinkBlockReason? reason;

  /// User-facing explanation, or null when allowed.
  final String? message;

  const DeepLinkDecision._({
    required this.isAllowed,
    this.path,
    required this.fallbackPath,
    this.reason,
    this.message,
  });

  const DeepLinkDecision.allow(String path)
    : this._(isAllowed: true, path: path, fallbackPath: kDeepLinkFallbackPath);

  const DeepLinkDecision.refuse(
    DeepLinkBlockReason reason,
    String message, {
    String fallbackPath = kDeepLinkFallbackPath,
  }) : this._(
         isAllowed: false,
         fallbackPath: fallbackPath,
         reason: reason,
         message: message,
       );
}

/// Answers "does this entity still exist, and can it be shown?".
///
/// Abstracted because the answer needs the network and the guard must not. The
/// production implementation is a Riverpod provider; tests supply a fake, which
/// is what makes every branch -- including a 404 racing a live session --
/// reachable without a server.
abstract class DeepLinkTargetProbe {
  Future<DeepLinkTargetState> probe(DeepLinkIntent intent);
}

/// Entities only a signed-in customer may open.
///
/// Browsing a product or a shop is public in this app (guest-first), but the
/// notification inbox and promotional offers are account-scoped: showing a
/// guest someone's personal offer list, or an inbox belonging to the previous
/// account on a shared device, is a privacy bug, not a UX nicety.
bool deepLinkRequiresAuthentication(DeepLinkEntity entity) => switch (entity) {
  DeepLinkEntity.offer => true,
  DeepLinkEntity.notification => true,
  DeepLinkEntity.product => false,
  DeepLinkEntity.shop => false,
  DeepLinkEntity.search => false,
};

/// Copy shown when a link is refused. Distinct per reason so the customer is
/// told *why* rather than getting a generic dead end, and so none of them
/// blame the customer or expose an internal id.
String deepLinkMessageFor(DeepLinkBlockReason reason) => switch (reason) {
  DeepLinkBlockReason.malformed => 'That link looks incomplete.',
  DeepLinkBlockReason.missingContext =>
    'One more step before we can open that.',
  DeepLinkBlockReason.unauthenticated => 'Please sign in to open that.',
  DeepLinkBlockReason.notFound => 'This content is no longer available.',
  DeepLinkBlockReason.unavailable => 'This is not available right now.',
};

/// Validates [intent] and returns where the customer should end up.
///
/// THE FOUR CHECKS, IN ORDER
/// ------------------------
/// The order is load-bearing, not cosmetic:
///
/// 1. **Entity exists** (form) -- a malformed id is refused without a network
///    call. Probing first would let a crafted link spam the backend.
/// 2. **Required context** -- app readiness. Navigating before the launch gates
///    clear is exactly how a cold-start tap gets swallowed by the splash
///    redirect, so this is checked before spending a request.
/// 3. **User auth state** -- account-scoped entities are refused for guests and
///    signed-out users, *before* probing, so a probe can never reveal whether a
///    private entity exists.
/// 4. **Entity exists / available** (reality) -- one probe, then `gone` and
///    `unavailable` are distinguished so the copy can be specific.
///
/// Every refusal carries a [DeepLinkDecision.fallbackPath], so "open this link"
/// can never end in a dead screen.
Future<DeepLinkDecision> evaluateDeepLink({
  required DeepLinkIntent intent,
  required DeepLinkEnvironment environment,
  required DeepLinkTargetProbe probe,
}) async {
  final path = deepLinkPathFor(intent);
  if (path == null) {
    return DeepLinkDecision.refuse(
      DeepLinkBlockReason.malformed,
      deepLinkMessageFor(DeepLinkBlockReason.malformed),
    );
  }

  if (!environment.isAppReady) {
    return DeepLinkDecision.refuse(
      DeepLinkBlockReason.missingContext,
      deepLinkMessageFor(DeepLinkBlockReason.missingContext),
    );
  }

  if (deepLinkRequiresAuthentication(intent.entity)) {
    final signedIn =
        environment.authStatus == AuthStatus.authenticated ||
        environment.authStatus == AuthStatus.otpSent;
    if (!signedIn) {
      return DeepLinkDecision.refuse(
        DeepLinkBlockReason.unauthenticated,
        deepLinkMessageFor(DeepLinkBlockReason.unauthenticated),
      );
    }
  }

  final state = await probe.probe(intent);
  switch (state) {
    case DeepLinkTargetState.available:
      return DeepLinkDecision.allow(path);
    case DeepLinkTargetState.gone:
      return DeepLinkDecision.refuse(
        DeepLinkBlockReason.notFound,
        deepLinkMessageFor(DeepLinkBlockReason.notFound),
      );
    case DeepLinkTargetState.unavailable:
      return DeepLinkDecision.refuse(
        DeepLinkBlockReason.unavailable,
        deepLinkMessageFor(DeepLinkBlockReason.unavailable),
      );
  }
}

/// A probe that approves everything.
///
/// Deliberately permissive. A deep link must never be the reason a customer
/// cannot reach a screen they could have reached by tapping, and a probe that
/// fails closed (denying on error) would break browsing for every customer with
/// a flaky connection. The guard's value is in refusing links that are *known*
/// bad -- gone, expired, or private -- not in second-guessing the server on
/// every tap.
class PermissiveDeepLinkProbe implements DeepLinkTargetProbe {
  const PermissiveDeepLinkProbe();

  @override
  Future<DeepLinkTargetState> probe(DeepLinkIntent intent) async =>
      DeepLinkTargetState.available;
}

final permissiveDeepLinkProbeProvider = Provider<DeepLinkTargetProbe>(
  (ref) => const PermissiveDeepLinkProbe(),
);
