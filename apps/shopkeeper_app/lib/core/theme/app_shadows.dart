/// Centralized elevation / shadow tokens — the SINGLE source of truth for
/// all box-shadows and card elevations in the app.
library;
import 'package:flutter/material.dart';

abstract final class AppShadows {
  AppShadows._();

  // ── Shadow inks ───────────────────────────────────────────────────
  // Reference these instead of writing raw `Color(0x…)` shadow values in
  // screens. Each is black at a fixed opacity.
  static const Color inkSubtle = Color(0x0A000000); // 4%
  static const Color inkSoft = Color(0x0D000000); // 5%
  static const Color inkFaint = Color(0x0F000000); // 6%
  static const Color inkMedium = Color(0x1A000000); // 10%
  static const Color inkAmbient = Color(0x12000000); // 7%
  static const Color inkStrong = Color(0x42000000); // 26%

  /// No shadow / flat surface (default for most cards).
  static const List<BoxShadow> none = [];

  /// Hairline drop shadow used by wizard / registration cards.
  static const List<BoxShadow> soft = [
    BoxShadow(color: inkSubtle, blurRadius: 6),
  ];

  /// Subtle elevation for input fields, small cards.
  static const List<BoxShadow> sm = [
    BoxShadow(
      color: inkSubtle,
      offset: Offset(0, 1),
      blurRadius: 2,
    ),
  ];

  /// Standard card / sheet elevation.
  static const List<BoxShadow> md = [
    BoxShadow(color: inkSoft, offset: Offset(0, 2), blurRadius: 4),
    BoxShadow(color: inkSubtle, offset: Offset(0, 1), blurRadius: 2),
  ];

  /// Elevated button / prominent card elevation.
  static const List<BoxShadow> lg = [
    BoxShadow(color: inkAmbient, offset: Offset(0, 4), blurRadius: 6),
    BoxShadow(color: inkSubtle, offset: Offset(0, 2), blurRadius: 4),
  ];

  /// Floating action button / modal elevation.
  static const List<BoxShadow> xl = [
    BoxShadow(color: inkMedium, offset: Offset(0, 8), blurRadius: 16),
    BoxShadow(color: inkFaint, offset: Offset(0, 4), blurRadius: 6),
  ];

  // Convenience elevation doubles (for Card.elevation)
  static const double elevationNone = 0.0;
  static const double elevationSm = 1.0;
  static const double elevationMd = 2.0;
  static const double elevationLg = 4.0;
  static const double elevationXl = 8.0;
}
