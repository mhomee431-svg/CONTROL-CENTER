import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Accessibility primitives shared across the app.
///
/// WHY A CENTRE, WHEN THE THEME ALREADY EXISTS
/// -------------------------------------------
/// `AppTypography` and `AppSpacing` own *values*. This owns the rules that are
/// easy to violate while still looking correct in code review:
///
///  * a touch target big enough to hit;
///  * a text size that did not fall below the legibility floor;
///  * a tap that a screen reader AND a keyboard can both reach;
///  * a status that is not carried by colour alone.
///
/// Each is small and easy to add inline, which is exactly how the 59 sub-12pt
/// sizes and the bare `GestureDetector`s got there. Centralising the rules means
/// a screen reaches for `A11y` instead of re-deriving them per file.
class A11y {
  const A11y._();

  // ── Touch targets ─────────────────────────────────────────────────────────
  /// Smallest reliably hittable target — the Material accessibility minimum,
  /// and what Android and iOS both recommend.
  ///
  /// Enforced through [tapTarget] rather than trusted to each widget, because a
  /// 24dp icon in a list row is the most common way a screen looks fine and is
  /// unusable for a customer with a tremor or a large thumb.
  static const double minTouchTarget = 48.0;

  /// Constrains [child] to at least [min] on both axes.
  ///
  /// Uses `constraints` rather than a fixed `SizedBox` so a control that is
  /// ALREADY larger keeps its own size: this only ever grows a target, never
  /// crops one.
  static Widget tapTarget({
    required Widget child,
    double min = minTouchTarget,
  }) {
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: min, minHeight: min),
      child: child,
    );
  }

  // ── Typography floor ──────────────────────────────────────────────────────
  /// The smallest size the UI will render text at.
  ///
  /// A plain `const` rather than a function: `const TextStyle` cannot call a
  /// method, and forcing every call site to drop `const` (rebuilding a style
  /// object on each build in a scrolling list) to satisfy a lint is the wrong
  /// trade. Since the floor is a constant, "the smallest permitted size" is
  /// itself a constant — callers write `fontSize: A11y.minFontSize`.
  static const double minFontSize = 12.0;

  // ── Screen-reader support ─────────────────────────────────────────────────
  /// Makes a tappable region reachable by a screen reader, a keyboard and a
  /// switch device.
  ///
  /// ## Why this exists instead of GestureDetector
  /// `GestureDetector` contributes NOTHING to the semantics tree on its own: no
  /// label, not focusable, not reported as a button. A screen reader walks
  /// straight past it and Tab/arrow navigation cannot reach it. Every bare
  /// `GestureDetector` in this app was therefore invisible to those users.
  ///
  /// ## Why the label wording matters
  /// The label is what gets announced, so it should describe the destination or
  /// outcome ("Open shop details"), not the widget ("card", "image") — the
  /// announcement should be useful, not a description of the layout.
  ///
  /// ## Why the action is declared explicitly
  /// `onTap` alone yields a node with no *action*: some screen readers announce
  /// it but cannot activate it. Declaring `tap` makes the node operable.
  static Widget tappable({
    required Widget child,
    required String label,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    bool button = true,
    bool enabled = true,
    String? value,
    bool excludeSemantics = false,
  }) {
    return Semantics(
      container: true,
      button: button,
      enabled: enabled,
      label: label,
      value: value,
      // A tappable region must not ALSO leak its children's labels: the reader
      // would announce "Dove Shampoo 240 rupees Gupta Electronics Open" and then
      // "Open shop details" as two separate stops, making the user assemble one
      // meaning from two.
      excludeSemantics: excludeSemantics,
      onTap: onTap == null ? null : () => onTap(),
      onLongPress: onLongPress,
      child: child,
    );
  }

  /// Hides a decorative region from assistive technology entirely.
  ///
  /// An icon that only repeats adjacent text, or a background flourish, should
  /// be skipped rather than announced. Making the intent explicit at the call
  /// site also covers plain widgets, which Flutter would otherwise walk into.
  static Widget decorative(Widget child) => ExcludeSemantics(child: child);

  /// Announces a live state change without stealing focus.
  ///
  /// For result counts and filter changes. Without `liveRegion` the new text
  /// appears silently for a screen-reader user, who then has no idea the search
  /// they requested actually ran.
  static Widget liveRegion({
    required Widget child,
    String? label,
    String? value,
  }) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: label,
      value: value,
      child: child,
    );
  }

  // ── Colour independence ───────────────────────────────────────────────────
  /// The ICON that pairs a status colour with a shape difference.
  ///
  /// Roughly 1 in 12 men has a colour-vision deficiency, and a red/green pair is
  /// the worst possible case: "in stock" (green) versus "out of stock" (red) is
  /// distinguished by hue alone in several of this app's badges. WCAG 1.4.1
  /// requires meaning to survive without colour, so status carries a shape and
  /// words as well as a hue.
  ///
  /// The caller supplies the text so wording stays with the feature that owns
  /// it; this only guarantees a non-colour signal exists.
  static IconData statusIcon({required bool positive, bool neutral = false}) {
    if (neutral) return Icons.info_outline;
    return positive ? Icons.check_circle : Icons.cancel;
  }

  // ── Keyboard / hardware input ─────────────────────────────────────────────
  /// Whether this platform routes keyboard input through the widget tree.
  ///
  /// True on desktop and web. Used to skip installing focus traversal on phones,
  /// so a capability those devices do not have costs nothing.
  static bool get hasKeyboardInput {
    final platform = defaultTargetPlatform;
    return platform == TargetPlatform.linux ||
        platform == TargetPlatform.macOS ||
        platform == TargetPlatform.windows;
  }

  /// Adds Enter/Space activation for keyboard users.
  ///
  /// Without this a screen-reader user can find a control through semantics but
  /// a pure keyboard user cannot reach it at all, because nothing on a touch
  /// screen is natively focusable.
  static Widget keyboardActivatable({
    required Widget child,
    VoidCallback? onActivate,
  }) {
    if (onActivate == null) return child;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): onActivate,
        const SingleActivator(LogicalKeyboardKey.space): onActivate,
      },
      child: child,
    );
  }
}
