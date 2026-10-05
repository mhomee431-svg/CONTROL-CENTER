import 'package:flutter/material.dart';

/// WCAG 2.1 contrast maths.
///
/// WHY THIS IS CODE AND NOT A DESIGN DOCUMENT
/// ------------------------------------------
/// Contrast is the one accessibility rule that silently rots: nothing crashes,
/// no test fails, and the colour still looks right to everyone reviewing it.
/// The only thing that catches it is an actual ratio, which is why the numbers
/// can be asserted in a test rather than trusted to whoever last picked a hex.
///
/// The ratios are computed with the WCAG relative-luminance formula, so what
/// the test asserts is exactly what a screen reader's contrast checker reports —
/// not an approximation of it.
class Contrast {
  const Contrast._();

  /// WCAG AA threshold for normal-size text.
  static const double aaNormal = 4.5;

  /// WCAG AA threshold for large text (>=18pt, or >=14pt bold).
  static const double aaLarge = 3.0;

  /// Relative luminance of [color], per WCAG 2.1.
  ///
  /// Uses Flutter's own [Color.computeLuminance], which already applies the
  /// sRGB transfer function. Re-deriving it here would risk the test asserting
  /// slightly different maths than the framework uses.
  static double luminance(Color color) =>
      color.computeLuminance().clamp(0.0, 1.0);

  /// Contrast ratio between [foreground] and [background], from 1.0 to 21.0.
  ///
  /// Order-independent: [contrast] and its arguments swapped give the same
  /// result, which is what WCAG specifies.
  static double ratio(Color foreground, Color background) {
    final a = luminance(foreground);
    final b = luminance(background);
    final lighter = a > b ? a : b;
    final darker = a > b ? b : a;
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// Whether [foreground] on [background] meets AA for normal text.
  static bool passesAa(Color foreground, Color background) =>
      ratio(foreground, background) >= aaNormal;

  /// Whether [foreground] on [background] meets AA for large text.
  static bool passesAaLarge(Color foreground, Color background) =>
      ratio(foreground, background) >= aaLarge;
}
