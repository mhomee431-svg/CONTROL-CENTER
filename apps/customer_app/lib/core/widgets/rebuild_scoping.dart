import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `ProviderListenable` is the narrowest type that still exposes `select`, and
// `flutter_riverpod.dart` does not re-export it — it lives in `misc.dart`.
// The `select` extension itself ships with `flutter_riverpod`, so importing
// this extra name is the only thing needed to type a watched provider.
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

/// Rebuilds ONLY the part of the UI that the selected value actually changes.
///
/// ## The concrete problem it solves
///
/// The audit found 136 `ref.watch` calls in this app, and the common shape was:
///
/// ```dart
/// final state = ref.watch(cartProvider);   // whole object
/// return Column(children: [
///   Text(state.title),                     // unchanged
///   Text(state.itemCount.toString()),      // only this changes, and often
/// ]);
/// ```
///
/// With a whole-object watch, an item-count change rebuilds the title and every
/// sibling. On a list screen this compounds into jank while scrolling. Watching
/// a projection instead means the count tick repaints the badge and nothing
/// else.
///
/// [WatchSelected] is the fix. It cannot be mistaken for a no-op wrapper the way
/// a bare "watch and pass a value" widget can, because the selector is a
/// required argument — you have to name WHICH value the widget depends on, and
/// that name is the documentation of the rebuild contract.
class WatchSelected<T, S> extends ConsumerWidget {
  const WatchSelected({
    required this.provider,
    required this.selector,
    required this.builder,
    super.key,
  });

  /// The provider to watch.
  ///
  /// Accepts a `Provider`, a `NotifierProvider`, and a `.family` of either,
  /// without the caller casting.
  final ProviderListenable<T> provider;

  /// Narrows [T] to the value this widget actually draws.
  ///
  /// The result MUST be comparable by `==` — that comparison is what decides
  /// whether to rebuild. Returning a fresh object every call (a list, a mapped
  /// model) defeats the whole mechanism and is the one way to misuse this.
  final S Function(T value) selector;

  /// Receives the selected value, and rebuilds only when it CHANGES.
  final Widget Function(BuildContext context, S value, WidgetRef ref) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return builder(context, ref.watch(provider.select(selector)), ref);
  }
}

/// Halts RASTERIZATION propagation into [child], so state changes above it do
/// not force its pixels to be recomputed.
///
/// This is specifically for a screen that watches a provider high up: a header
/// counter that ticks once a second would otherwise re-rasterize an entire
/// 30-tile product grid below it. With this boundary, only the header repaints.
///
/// ## It does not stop the BUILD phase
///
/// If the parent rebuilds, this widget's subtree is still built. To stop builds,
/// watch narrowly with [WatchSelected] instead. The two are complementary:
/// narrow the watch to cut builds, add this to cut paints.
///
/// ## Keep scroll position separately
///
/// This does not preserve scroll offset. For that, give the list a
/// [PageStorageKey] and keep its [ScrollController] in a `State` that outlives
/// the rebuild — the scroll-position problem is a state-lifetime problem, not a
/// paint problem, and claiming otherwise here would hide a real bug.
class RepaintIsolated extends StatelessWidget {
  const RepaintIsolated({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => RepaintBoundary(child: child);
}
