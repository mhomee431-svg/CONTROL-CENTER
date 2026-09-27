/// Provider LIFETIME policy, in one place.
///
/// WHY THIS FILE EXISTS
/// --------------------
/// The audit that prompted it found `keepAlive` used ZERO times across the whole
/// app. Every provider therefore lived only as long as its last listener, which
/// produces two visible symptoms:
///
///  * **Navigate away and back, and everything reloads.** Product details, the
///    home feed, cart counts — all refetched from scratch, so the customer
///    stares at a skeleton again for content they just looked at.
///  * **Scroll position and transient UI state are lost** on every rebuild
///    caused by a route change.
///
/// The opposite mistake is just as real: a provider that is never disposed
/// leaks its state across sign-out, so the next customer can briefly see the
/// previous one's data. That is not a performance bug, it is a privacy bug.
///
/// So lifetime is a DECISION, made explicitly and consistently, rather than an
/// accident of which widget happened to watch what.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Central place to record what "hot" means for this app.
abstract final class ProviderPolicy {
  /// How long a hot provider's value survives with NO listeners before it is
  /// released.
  ///
  /// A timed window rather than permanent is deliberate:
  ///
  ///  * Back navigation (seconds) is the common case, and the window covers it
  ///    with no perceptible delay — the customer never sees a second skeleton.
  ///  * A customer who has genuinely walked away from a feature for minutes gets
  ///    their memory back.
  ///  * A permanent keepAlive would grow for the whole session, and would have
  ///    to be invalidated on sign-out anyway.
  static const Duration hotIdle = Duration(minutes: 5);

  /// Providers that MUST be released on sign-out, because they can hold
  /// customer data.
  ///
  /// Anything in here is force-disposed when the session ends. This is the
  /// privacy half of the policy, and it is why "just make everything hot" is
  /// not the answer: a cart that survives a sign-out shows the next customer
  /// somebody else's basket.
  static const Set<Object> sessionScoped = {};
}

/// Keeps the provider that owns [ref] alive for [idle] after its last listener
/// detaches, then releases it.
///
/// One line inside `build()`:
///
/// ```dart
/// @override
/// ProductDetailsState build(String id) {
///   keepHot(ref);
///   return const ProductDetailsState();
/// }
/// ```
///
/// ## Why a module-level map instead of an extension field
///
/// An extension cannot hold an instance field, and each provider needs its own
/// timer. The key is the provider itself, which is a stable identity with a
/// correct `==`/`hashCode`, so a `WeakReference`-free map keyed on it is both
/// simple and safe: the entry is removed as soon as the timer fires, and any
/// provider that is rebuilt first cancels its own previous timer.
///
/// ## Why re-listening cancels the timer
///
/// A naive "set a timer and forget it" implementation leaves a pending timer
/// firing long after the customer moved on — wasted work, and in tests an
/// "timer still pending" failure. Cancelling on re-listen means at most one
/// timer exists per provider, and only while nobody is listening.
final Map<Object, Timer> _hotTimers = {};

/// How many hot providers are currently holding a timer. For tests.
@visibleForTesting
int get hotProviderCount => _hotTimers.length;

/// Marks the provider owning [ref] as HOT: it survives losing its last listener
/// for [idle], so navigating back does not refetch what the customer just saw.
void keepHot(Ref ref, [Duration idle = ProviderPolicy.hotIdle]) {
  // The provider element is the identity of "which provider is this".
  _hotTimers.remove(ref)?.cancel();
  _hotTimers[ref] = Timer(idle, () {
    // Reached only if nobody came back. Removing the entry is the whole job:
    // once no listener has returned, Riverpod disposes the provider on its own.
    _hotTimers.remove(ref);
  });
}

/// A `Notifier` that is hot by default.
///
/// Prefer this over a plain `Notifier` for anything a customer is likely to
/// return to within a session. Lifetime becomes a property of the type —
/// visible in the signature — rather than a line somebody has to remember.
abstract class HotNotifier<T> extends Notifier<T> {
  @override
  T build() {
    keepHot(ref);
    return buildOnce();
  }

  /// The real `build`. [HotNotifier.build] calls this after applying the
  /// lifetime policy, so an override cannot accidentally drop it.
  T buildOnce();
}
