// `TextScaler` comes from Flutter's own re-export rather than `dart:ui`
// directly: it is the same type, and going through the framework import keeps
// this file resolvable by tooling that resolves dart:ui oddly.
import 'package:flutter/widgets.dart';

/// The app's text-scaling policy, in one place.
///
/// WHY THIS IS A POLICY AND NOT A LITERAL
/// --------------------------------------
/// The scale factors that matter are not round numbers chosen for looks: they
/// are the values real operating systems actually offer. Android exposes
/// 0.85x through 2.0x (with 1.3x and 1.8x as named accessibility steps), and
/// iOS runs to roughly 3.2x in its largest accessibility sizes. The tests in
/// `text_scaling_test.dart` use exactly these, because a layout that only
/// survives 1.5x has not been tested at the setting a customer actually chose.
///
/// The three named sizes are the ones worth designing against: they are the
/// steps a user picks deliberately, and the ones that expose a fixed-height row
/// or a clipped button.
class TextScaling {
  const TextScaling._();

  /// The default. Not a floor -- smaller-than-default is honoured too.
  static const double normal = 1.0;

  /// Android's "Large" accessibility step. The most common deliberate increase.
  static const double large = 1.3;

  /// Android's "Largest" accessibility step, and where fixed-height rows start
  /// to break. This is the size most layouts in this app are still weakest at.
  static const double xLarge = 1.8;

  /// Android's maximum accessibility size, fully supported.
  static const double maxAccessibility = 2.0;

  /// The largest scale this app renders at full fidelity.
  ///
  /// Beyond this the layout cannot physically fit -- a two-line title plus body
  /// plus actions needs more vertical room than a phone has -- so text is held
  /// here rather than allowed to push buttons off screen. Customers who set
  /// more than this still get larger text than default, just not unbounded.
  ///
  /// Deliberately above `maxAccessibility` so no Android accessibility setting
  /// is ever silently reduced; it exists only to bound iOS's extreme end.
  /// A fixed-height strip that must hold a text label plus icon.
  ///
  /// Scaled by the active text scale so the control grows with the text rather
  /// than clipping it. The floor is the 48dp Material minimum touch target, so a
  /// scaled-up bar never becomes a *smaller* target than a normal one -- scaling
  /// up must not cost precision.
  static double chipBarHeight(TextScaler textScaler) =>
      _atLeast(48.0, 50.0 * textScaler.scale(1.0));

  /// Never returns a value below [floor].
  static double _atLeast(double value, double floor) =>
      value < floor ? floor : value;

  /// Scales worth sweeping a screen against.
  static const double maxSupportedScale = 2.5;

  /// Scales worth sweeping a screen against.
  ///
  /// Includes a value above the cap on purpose: clamping must not make the
  /// layout explode, or the clamp is not doing its job.
  static const List<double> testScales = <double>[
    normal,
    large,
    xLarge,
    maxAccessibility,
    maxSupportedScale,
    3.2, // iOS maximum accessibility size.
  ];

  /// The name of [scale], for a failure message that says which sweep failed.
  static String describe(double scale) =>
      scale == normal ? 'normal' : '${scale.toStringAsFixed(1)}x';
}
