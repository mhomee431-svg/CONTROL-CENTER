import 'package:flutter/foundation.dart';

import '../data/provider_policy.dart';
import 'load_state.dart';

/// The base class every ViewModel in this app extends.
///
/// WHAT A VIEWMODEL OWNS (per the project ViewModel rule)
/// -----------------------------------------------------
/// UI state, commands, loading, error, filter state, search state, pagination
/// state, mutation state. All of it, and only that.
///
/// ## The single most important thing it must NOT do
///
/// A ViewModel must not know what a Widget is. It never imports
/// `package:flutter/material.dart`, never holds a `BuildContext`, and never
/// calls `setState`. It exposes a plain immutable state object plus methods
/// (commands); the view decides how to render it.
///
/// That separation is what makes the ViewModel testable with no widget pumping
/// at all — you assert on state, not on pixels — and it is why this base class
/// imports `foundation`, not `widgets`.
///
/// ## Lifetime
///
/// Extends [HotNotifier] so the provider survives a brief loss of listeners.
/// That is what stops a customer navigating to a detail screen and back from
/// seeing a second skeleton for content they were just reading. Use
/// [autoDispose] only for a screen that is genuinely single-use.
abstract class ViewModel<S> extends HotNotifier<S> {
  @override
  S build() {
    keepHot(ref);
    return initialState();
  }

  /// The state before anything is loaded.
  ///
  /// Defaults to the idle case, which is the honest starting point: the
  /// ViewModel has not asked for anything yet. A subclass that genuinely cannot
  /// render without data overrides this.
  @protected
  S initialState();

  /// Convenience for subclasses: run [command] as a load, publishing
  /// [LoadState] transitions without repeating try/catch.
  ///
  /// Guarantees the three things a hand-rolled version forgets:
  /// 1. a failure cannot leave the state stuck in "loading" forever,
  /// 2. the previous value survives a failed refresh, and
  /// 3. a result that "succeeded but was empty" is reported as [LoadEmpty],
  ///    not silently as a success with nothing in it.
  ///
  /// [D] is the type the view renders; [R] is what the repository returns.
  /// They are separate because reshaping a raw result into a display model is
  /// exactly the work a ViewModel is supposed to own.
  @protected
  Future<void> runLoad<D, R>(
    LoadState<D> Function(LoadState<D> current) publish,
    Future<R> Function() command, {
    required D Function(R value) toDisplay,
    bool Function(R value)? isEmpty,
  }) async {
    final current = publish(LoadState<D>.loading());
    try {
      final result = await command();
      if (isEmpty?.call(result) ?? false) {
        publish(LoadState<D>.empty());
      } else {
        publish(LoadReady<D>(toDisplay(result)));
      }
    } catch (error, stack) {
      // Debug-log the stack, never surface it: the view must get a friendly
      // message, and raw exception text is not customer-safe.
      assert(() {
        debugPrint('ViewModel load failed: $error\n$stack');
        return true;
      }());
      publish(LoadFailed<D>(error, current.dataOrNull));
    }
  }
}
