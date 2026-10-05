import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/controllers/auth_controller.dart';
import '../../features/onboarding/presentation/controllers/onboarding_controller.dart';
import '../../features/product_details/domain/product_details_repository.dart';
import '../../features/shop_details/domain/shop_details_repository.dart';
import '../network/api_error_handler.dart';
import 'deep_link.dart';
import 'deep_link_guard.dart';

/// The production probe: asks the repositories whether the entity still exists.
///
/// This is the only part of deep linking that touches the network, and it is
/// kept behind [DeepLinkTargetProbe] so the guard stays pure and testable.
///
/// WHY A 404 IS "GONE" BUT EVERY OTHER FAILURE IS "AVAILABLE"
/// --------------------------------------------------------
/// A 404 is *authoritative*: the server has been asked about this exact entity
/// and answered that it does not exist. Treating that as "available" opens a
/// detail screen for a product the shopkeeper deleted, and the customer's only
/// option there is an error-and-retry state whose retry can never succeed.
///
/// Every *other* failure -- no network, a timeout, a 500, a 401, or even an
/// unexpected exception -- cannot tell us whether the entity exists, so it is
/// reported as available and the screen is opened. The detail screen renders its
/// own error-and-retry state for a failed fetch; refusing the link here would
/// replace a recoverable screen with a dead end, which is strictly worse.
///
/// A 401/403 is deliberately NOT treated as "gone": a signed-out or
/// unauthorised customer must not be told a product has been deleted, and the
/// guard already refuses those links earlier for being account-scoped.
class RepositoryDeepLinkProbe implements DeepLinkTargetProbe {
  final ProductDetailsRepository products;
  final ShopDetailsRepository shops;

  RepositoryDeepLinkProbe({required this.products, required this.shops});

  @override
  Future<DeepLinkTargetState> probe(DeepLinkIntent intent) async {
    try {
      switch (intent.entity) {
        case DeepLinkEntity.product:
          await products.getProductDetails(intent.id);
          return DeepLinkTargetState.available;
        case DeepLinkEntity.shop:
          await shops.getShopProfile(intent.id);
          return DeepLinkTargetState.available;
        // Offers have no backing screen or API in this build yet, so the route
        // exists purely to degrade gracefully. Report the fact rather than
        // pretending the offer is live.
        case DeepLinkEntity.offer:
          return DeepLinkTargetState.unavailable;
        // A search and the inbox are not entity-addressed: there is nothing to
        // look up, and those screens render their own empty states.
        case DeepLinkEntity.search:
        case DeepLinkEntity.notification:
          return DeepLinkTargetState.available;
      }
    } on ApiException catch (e) {
      // Only an authoritative "no such entity" is evidence of absence.
      return e.type == ApiErrorType.notFound
          ? DeepLinkTargetState.gone
          : DeepLinkTargetState.available;
    } catch (_) {
      // Anything unexpected tells us nothing about the entity's existence, so
      // the link is allowed through and the screen reports its own failure.
      return DeepLinkTargetState.available;
    }
  }
}

final deepLinkTargetProbeProvider = Provider<DeepLinkTargetProbe>((ref) {
  return RepositoryDeepLinkProbe(
    products: ref.watch(productDetailsRepositoryProvider),
    shops: ref.watch(shopDetailsRepositoryProvider),
  );
});

/// Builds the [DeepLinkEnvironment] the guard needs, from live app state.
///
/// The readiness rule mirrors the router's own `redirect` gate: navigating
/// before the session and onboarding flag have resolved would have the
/// navigation immediately undone by a redirect to `/splash`.
final deepLinkEnvironmentProvider = Provider<DeepLinkEnvironment>((ref) {
  final auth = ref.watch(authControllerProvider);
  final onboarding = ref.watch(onboardingCompletedProvider);
  return DeepLinkEnvironment(
    authStatus: auth.status,
    isAppReady:
        onboarding == true &&
        auth.status != AuthStatus.initial &&
        auth.status != AuthStatus.loading,
    now: DateTime.now(),
  );
});

/// Validates [raw] and reports where the customer should end up.
///
/// Pure with respect to navigation: this decides, it does not act. The
/// launcher below is what moves.
final deepLinkDecisionProvider =
    Provider.family<Future<DeepLinkDecision>, String>((ref, raw) {
      final intent = parseDeepLink(raw);
      if (intent == null) {
        return Future.value(
          const DeepLinkDecision.refuse(
            DeepLinkBlockReason.malformed,
            'That link looks incomplete.',
          ),
        );
      }
      return evaluateDeepLink(
        intent: intent,
        environment: ref.watch(deepLinkEnvironmentProvider),
        probe: ref.watch(deepLinkTargetProbeProvider),
      );
    });

/// Opens a deep link, or degrades to a real screen explaining why not.
///
/// The single entry point every link goes through -- a notification tap, a
/// shared URL, a cold-start argument. It guarantees three things:
///
///  * navigation only ever happens to a path the guard approved;
///  * a refused link still lands the customer somewhere, never on a 404;
///  * navigation failures (unmounted context, an unknown route) degrade to the
///    same fallback instead of throwing into a gesture callback.
class DeepLinkLauncher {
  final Ref _ref;

  DeepLinkLauncher(this._ref);

  /// Resolves [raw] and navigates. Returns the decision that was acted on, so
  /// callers and tests can assert on the outcome rather than on side effects.
  Future<DeepLinkDecision> open(
    BuildContext context,
    String? raw, {
    bool usePush = false,
  }) async {
    // Resolve the router and messenger BEFORE awaiting the decision.
    //
    // The decision may probe the network, and holding a BuildContext across
    // that await is a real hazard (the screen can be disposed mid-probe) as
    // well as a lint. Grabbing the two collaborators up front means everything
    // after the await is plain object calls, with no context involved at all.
    GoRouter router;
    ScaffoldMessengerState messenger;
    try {
      router = GoRouter.of(context);
      messenger = ScaffoldMessenger.of(context);
    } catch (_) {
      // No router in this subtree: the customer is already somewhere that
      // cannot navigate. Report the refusal without touching the tree.
      return const DeepLinkDecision.refuse(
        DeepLinkBlockReason.missingContext,
        'We could not open that right now.',
      );
    }

    final decision = await _ref.read(deepLinkDecisionProvider(raw ?? ''));

    if (decision.isAllowed) {
      try {
        if (usePush) {
          router.push(decision.path!);
        } else {
          // `go` replaces the stack, so a cold-start link does not leave
          // `/splash` underneath for a single "back" to return to.
          router.go(decision.path!);
        }
        return decision;
      } catch (_) {
        // A route this build does not register. Fall through to the same safe
        // landing rather than throwing into a gesture callback.
        return _fallback(router, messenger, decision);
      }
    }

    return _fallback(router, messenger, decision);
  }

  DeepLinkDecision _fallback(
    GoRouter router,
    ScaffoldMessengerState messenger,
    DeepLinkDecision decision,
  ) {
    try {
      router.go(decision.fallbackPath);
      final message = decision.message;
      if (message != null && message.isNotEmpty) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(message),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    } catch (_) {
      // Nothing left to do: the customer stays wherever they were, which is
      // still a working screen.
    }
    return decision;
  }
}

final deepLinkLauncherProvider = Provider<DeepLinkLauncher>(
  (ref) => DeepLinkLauncher(ref),
);
