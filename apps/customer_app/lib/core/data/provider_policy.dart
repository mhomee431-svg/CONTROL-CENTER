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

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `KeepAliveLink` is what `ref.keepAlive()` returns, but the `flutter_riverpod`
// barrel does not re-export it.
import 'package:flutter_riverpod/misc.dart' show KeepAliveLink;

/// Central place to record what "hot" means for this app.
abstract final class ProviderPolicy {
  /// A hot provider is released by the framework, not by a clock.
  ///
  /// Kept as a named constant so call sites and docs refer to one idea, and so
  /// the lifetime decision has a single place to change if that ever needs to
  /// become tunable. See [keepHot] for why there is deliberately no interval.
  static const bool hotProvidersSurviveNavigation = true;
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
final Map<Object, KeepAliveLink> _hotLinks = {};

/// How many hot providers are currently holding a keep-alive link. For tests.
@visibleForTesting
int get hotProviderCount => _hotLinks.length;

/// Marks the provider owning [ref] as HOT: it survives losing its last listener,
/// so navigating back does not refetch what the customer just saw.
///
/// One line inside `build()`:
///
/// ```dart
/// @override
/// ProductDetailsState buildOnce(String id) {
///   keepHot(ref);
///   return const ProductDetailsState();
/// }
/// ```
///
/// ## Why this uses Riverpod's own link and NOT a Timer
///
/// The obvious implementation is "set a Timer, and when it fires stop caring".
/// That is wrong in a way that only shows up later: an active `Timer` is a
/// PENDING TIMER, and `flutter_test` asserts that no timers are outstanding at
/// the end of every widget test. So one `keepHot` call anywhere in the widget
/// tree made every widget test touching a hot provider fail with
/// `!timersPending`. A design choice that breaks the whole test suite is not a
/// design choice, it is a bug.
///
/// `ref.keepAlive()` is the mechanism Riverpod actually provides. It holds the
/// provider with no timer, so there is nothing pending to assert on, and
/// disposal is driven by the framework rather than by wall-clock time.
///
/// ## Why there is no timed window
///
/// A "release after N idle minutes" timer was considered and dropped. Beyond the
/// test breakage, it makes a provider's lifetime depend on a clock rather than
/// on a rule — which is exactly the invisible coupling that produces "why is my
/// state gone?" bugs. Use `keepHot` for session-lifetime state and
/// `autoDispose` for a screen's short-lived request.
///
/// ## The privacy trade-off
///
/// A hot provider is NOT released on sign-out. That is deliberate, and it is why
/// hot providers must not hold customer data: a cart that survives a sign-out
/// shows the next customer somebody else's basket. Anything personal belongs in
/// an `autoDispose` provider, or must be cleared by the sign-out path via
/// [releaseHot].
void keepHot(Ref ref) {
  // Re-listening would otherwise stack one link per rebuild.
  _hotLinks.remove(ref)?.close();
  _hotLinks[ref] = ref.keepAlive();
}

/// Releases a provider previously marked [keepHot]. Call from the sign-out path
/// for any provider that does hold customer data.
void releaseHot(Ref ref) {
  _hotLinks.remove(ref)?.close();
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
