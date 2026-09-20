/// Centralized typography tokens — the SINGLE source of truth for all text
/// styles in the app.
///
/// Uses `google_fonts` Inter for a consistent, modern business interface.
library;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

abstract final class AppTypography {
  AppTypography._();

  /// Base text theme using Google Fonts Inter.
  static final TextTheme base = GoogleFonts.interTextTheme();

  /// The working text theme for [brightness].
  ///
  /// [base] is a font-only theme: its styles carry no colour. Assigning it
  /// straight to `ThemeData.textTheme` therefore strips Material's
  /// brightness-aware ink, and text falls back to the painter default (black)
  /// — invisible on the dark surface. Re-applying ink here keeps text readable
  /// in both modes, with the secondary slots a step below the primary ink so
  /// the existing hierarchy survives.
  static TextTheme themeFor(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final ink = isDark ? AppColors.darkTextOnDark : AppColors.darkText;
    final muted = isDark ? AppColors.textMutedOnDark : AppColors.textMuted;
    return base.apply(bodyColor: ink, displayColor: ink).copyWith(
      bodyMedium: base.bodyMedium?.copyWith(color: muted),
      bodySmall: base.bodySmall?.copyWith(color: muted),
      labelMedium: base.labelMedium?.copyWith(color: muted),
      labelSmall: base.labelSmall?.copyWith(color: muted),
    );
  }

  // ── Display ───────────────────────────────────────────────────────
  static final displayLarge = base.displayLarge?.copyWith(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: AppColors.darkText,
      ) ??
      const TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: AppColors.darkText,
      );

  static final displayMedium = base.displayMedium?.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: AppColors.darkText,
      ) ??
      const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: AppColors.darkText,
      );

  // ── Headings ──────────────────────────────────────────────────────
  static final headingLarge = base.headlineLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: AppColors.darkText,
      ) ??
      const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: AppColors.darkText,
      );

  static final headingMedium = base.headlineMedium?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.darkText,
      ) ??
      const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.darkText,
      );

  static final headingSmall = base.headlineSmall?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.darkText,
      ) ??
      const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.darkText,
      );

  // ── Body ──────────────────────────────────────────────────────────
  static final bodyLarge = base.bodyLarge?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: AppColors.darkText,
      ) ??
      const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: AppColors.darkText,
      );

  static final bodyMedium = base.bodyMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.darkText,
      ) ??
      const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.darkText,
      );

  static final bodySmall = base.bodySmall?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: AppColors.textMuted,
      ) ??
      const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: AppColors.textMuted,
      );

  // ── Labels ────────────────────────────────────────────────────────
  static final labelLarge = base.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.darkText,
      ) ??
      const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.darkText,
      );

  static final labelMedium = base.labelMedium?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.darkText,
      ) ??
      const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.darkText,
      );

  // ── Caption / footnote ────────────────────────────────────────────
  /// Footnote / meta text.
  ///
  /// Colourless on purpose. `base.bodySmall` carries Material's baseline ink
  /// (#1D1B20): readable on the light surface, but ~1.05:1 on the dark one.
  /// Building it through `GoogleFonts.inter` with a colour-free style keeps the
  /// Inter family while leaving the ink to the resolved, brightness-aware
  /// `DefaultTextStyle`.
  static final caption = GoogleFonts.inter(
    textStyle: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w400,
    ),
  );
}
