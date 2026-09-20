import 'package:flutter/widgets.dart';

/// One policy for how the app reacts to the platform font-size setting.
///
/// Every screen is built from intrinsic layouts (`Expanded` / `Flexible` /
/// scroll views), so most of the UI already reflows when text grows. What does
/// not reflow on its own is the handful of boxes with a design height (CTA
/// buttons, segmented labels, chips) and the two-column dashboard stat grid.
/// Rather than sprinkle `textScaler:` overrides across widgets — which is how
/// text-scaling support rots — the whole app is clamped once, in [apply].
///
///  * [minScaleFactor] is a readability floor for dense stock/price tables: a
///    shopkeeper who picks an unusually small system font still gets legible
///    labels.
///  * [maxScaleFactor] is the largest scale the current layouts are built and
///    checked for. Raising it means re-verifying the fixed-height chips/badges
///    and the dashboard stat grid at the new ceiling.
abstract final class TextScalePolicy {
  /// Never render user-facing text below this factor.
  static const double minScaleFactor = 0.85;

  /// Never render user-facing text above this factor (see class docs).
  static const double maxScaleFactor = 1.3;

  /// Clamps one platform scale factor into the supported band.
  ///
  /// Non-positive and NaN values — which a misbehaving platform channel can
  /// produce — fall back to `1.0` (the default) instead of propagating into
  /// layout.
  static double clamp(double scaleFactor) {
    if (scaleFactor.isNaN || scaleFactor <= 0) return 1;
    return scaleFactor.clamp(minScaleFactor, maxScaleFactor);
  }

  /// Wraps the app so every descendant sees the clamped text scale.
  static Widget apply(Widget child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: minScaleFactor,
        maxScaleFactor: maxScaleFactor,
        child: child,
      );
}
