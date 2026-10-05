import 'dart:async';

import 'package:flutter/material.dart';

/// Shared pressed / loading / disabled behaviour for controls that start work.
///
/// ## Why this exists
/// -----------------
/// The app has ~189 button widgets and roughly 18 of them start async work.
/// Every one of those was re-deriving the same three questions, and they did
/// not agree on the answers:
///
///  * **Is the control disabled while busy?** Some screens read a status flag
///    (`onPressed: state.isLoading ? null : _go`), some held a local `bool`,
///    and some held nothing at all. A screen with no guard fires the action
///    twice.
///  * **Does the tap itself get blocked, or just the button?** Setting
///    `onPressed: null` only takes effect on the NEXT rebuild. Two taps inside
///    one frame — or a fast double-tap while the network call is in flight —
///    both reach the handler before any rebuild happens. For "Place order" or
///    "Send OTP" that is a real duplicate, not a theoretical one.
///  * **Is pressed state visible?** Without it, a tap on a slow button looks
///    like nothing happened, which is exactly when customers tap again.
///
/// This settles all three in one place: it blocks re-entry SYNCHRONOUSLY on
/// the first tap, reflects that as disabled + loading, and clears the block
/// when the work finishes.
class ActionButton extends StatefulWidget {
  const ActionButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.loadingLabel,
    this.busyLabel,
    this.disabled = false,
    this.variant = ActionButtonVariant.filled,
    this.showProgress = true,
  });

  /// The work to start. May return a `Future`, which is awaited to decide when
  /// the button becomes tappable again.
  final FutureOr<void> Function()? onPressed;

  /// The resting content — normally the label.
  final Widget child;

  /// Shown while busy. Defaults to [child].
  final Widget? loadingLabel;

  /// Announced to assistive tech while busy.
  final String? busyLabel;

  /// Disables the control for a reason unrelated to being busy.
  final bool disabled;

  final ActionButtonVariant variant;

  /// Whether to swap in a spinner while busy.
  ///
  /// False for controls whose label already reads as progress
  /// ("Submitting…"), where a second spinner is noise.
  final bool showProgress;

  @override
  State<ActionButton> createState() => _ActionButtonState();
}

enum ActionButtonVariant { filled, outlined, text }

class _ActionButtonState extends State<ActionButton> {
  /// Set SYNCHRONOUSLY in the tap handler, before awaiting.
  ///
  /// This is the part that matters. A flag applied in `setState` alone still
  /// leaves a window: two taps in the same frame both read the old value. Only
  /// mutating the field before the first `await` closes that window.
  bool _busy = false;

  bool get _enabled => widget.onPressed != null && !widget.disabled && !_busy;

  Future<void> _handleTap() async {
    // Re-entrancy guard. Later taps are dropped outright rather than queued:
    // a customer who taps twice did not mean to do the thing twice.
    if (_busy) return;
    final action = widget.onPressed;
    if (action == null || widget.disabled) return;

    _busy = true;
    if (mounted) setState(() {});

    try {
      await action();
    } finally {
      // Released even if the action throws, or a failed request leaves the
      // control permanently dead with no way to retry — the worst outcome,
      // since the customer faces a button that does nothing and gives no
      // reason why.
      _busy = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled;
    final onPressed = enabled ? _handleTap : null;

    // The spinner is wrapped so a screen reader announces the busy state
    // instead of silently re-reading the original label while work is in flight.
    final content = _busy && widget.showProgress
        ? Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator.adaptive(strokeWidth: 2),
              ),
              if (widget.loadingLabel != null) ...[
                const SizedBox(width: 10),
                widget.loadingLabel!,
              ],
            ],
          )
        : (_busy ? widget.loadingLabel : null) ?? widget.child;

    return Semantics(
      button: true,
      enabled: enabled,
      child: switch (widget.variant) {
        ActionButtonVariant.filled => FilledButton(
          onPressed: onPressed,
          child: content,
        ),
        ActionButtonVariant.outlined => OutlinedButton(
          onPressed: onPressed,
          child: content,
        ),
        ActionButtonVariant.text => TextButton(
          onPressed: onPressed,
          child: content,
        ),
      },
    );
  }
}

/// Wraps an arbitrary control (an [IconButton], a card, an [InkWell]) with the
/// same duplicate-tap protection.
///
/// For the many tappable things in this app that are not buttons — quantity
/// steppers, favourite hearts, filter chips — where dropping to an
/// [ActionButton] would change the visual design but the double-fire risk is
/// identical.
///
/// Note this swallows only a *double* tap, not the whole duration of an async
/// call: the block is released after the next frame. Use [ActionButton] when the
/// work is genuinely async and must not be re-triggered until it completes.
class TapGuard extends StatefulWidget {
  const TapGuard({
    super.key,
    required this.child,
    required this.onTap,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  State<TapGuard> createState() => _TapGuardState();
}

class _TapGuardState extends State<TapGuard> {
  bool _busy = false;

  void _handleTap() {
    if (_busy || !widget.enabled) return;
    final action = widget.onTap;
    if (action == null) return;

    _busy = true;
    setState(() {});

    action();

    // Released on the next frame rather than immediately: the point is to
    // swallow the second tap of a double-tap, which lands in the same frame or
    // the one after. Holding it across exactly one frame is what makes the guard
    // work without leaving the control feeling sticky afterwards.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _busy = false;
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Null while busy, which is what actually drops the second tap — the
      // detector stops claiming the hit test entirely.
      onTap: (_busy || !widget.enabled) ? null : _handleTap,
      child: widget.child,
    );
  }
}
