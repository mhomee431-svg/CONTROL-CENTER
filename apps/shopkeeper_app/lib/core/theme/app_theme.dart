/// Shopkeeper App theme — business-console look, mobile-first.
///
/// All color, typography, spacing, radius, shadow, button, input, and card
/// values are defined in the centralized token files under `lib/core/theme/`.
/// This file composes them into a `ThemeData`.
library;

import 'package:flutter/material.dart';

import 'app_button_styles.dart';
import 'app_card_styles.dart';
import 'app_colors.dart';
import 'app_input_styles.dart';
import 'app_typography.dart';

class AppTheme {
  AppTheme._();

  // ── Legacy color aliases (backward-compat for screens not yet migrated) ──
  /// @deprecated Use [AppColors.primary] — HyperLocal royal blue.
  static const Color brandSeed = AppColors.primary;

  /// @deprecated Use [AppColors.orange].
  static const Color accent = AppColors.orange;

  /// @deprecated Use [AppColors.verifiedGreen].
  static const Color verifiedGreen = AppColors.verifiedGreen;

  /// @deprecated Use [AppColors.pendingAmber].
  static const Color pendingAmber = AppColors.pendingAmber;

  /// @deprecated Use [AppColors.rejectedRed].
  static const Color rejectedRed = AppColors.rejectedRed;

  /// @deprecated Use [AppColors.suspendedGrey].
  static const Color suspendedGrey = AppColors.suspendedGrey;

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: AppColors.onPrimary,
        primaryContainer: AppColors.primaryContainer,
        onPrimaryContainer: AppColors.onPrimary,
        secondary: AppColors.green,
        onSecondary: AppColors.onPrimary,
        tertiary: AppColors.tertiary,
        onTertiary: AppColors.onTertiary,
        surface: AppColors.surface,
        onSurface: AppColors.darkText,
        error: AppColors.error,
        onError: AppColors.white,
        // `outline` has a dual role in this app: it is the border of inputs
        // (M3's default) *and* the colour of secondary/meta TEXT — 148 call
        // sites do `color: scheme.outline`. borderGray (#E2E8F0) is only
        // ~1.2:1 on white: unreadable as text and below the 3:1 WCAG 1.4.11
        // asks of input borders. textMuted passes AA (4.75:1) for text and
        // 3:1 for UI. Dividers use `outlineVariant` and stay subtle.
        outline: AppColors.textMuted,
        outlineVariant: AppColors.lightGray,
        surfaceContainerHigh: AppColors.lightGray,
        surfaceContainerLowest: AppColors.white,
      ),
    );
    return base.copyWith(
      // Colour-aware text theme. `AppTypography.base` alone is font-only
      // (colourless) — see AppTypography.themeFor.
      textTheme: AppTypography.themeFor(Brightness.light),
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.darkText,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: AppColors.darkText),
        titleTextStyle: AppTypography.headingMedium,
      ),
      cardTheme: AppCardStyles.standard,
      filledButtonTheme: FilledButtonThemeData(style: AppButtonStyles.filled),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: AppButtonStyles.elevated,
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: AppButtonStyles.outlined,
      ),
      textButtonTheme: TextButtonThemeData(style: AppButtonStyles.text),
      inputDecorationTheme: AppInputStyles.theme,
    );
  }

  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        onPrimary: AppColors.onPrimary,
        primaryContainer: AppColors.primaryContainer,
        onPrimaryContainer: AppColors.onPrimary,
        secondary: AppColors.green,
        onSecondary: AppColors.onPrimary,
        tertiary: AppColors.tertiary,
        onTertiary: AppColors.onTertiary,
        surface: AppColors.surfaceDark,
        onSurface: AppColors.darkTextOnDark,
        error: AppColors.error,
        onError: AppColors.white,
        // Same dual role as in [light]: secondary/meta text *and* input
        // borders. textMutedOnDark keeps ≥4.5:1 on the dark surface — the
        // previous near-white outline read fine as text but was far too loud
        // for borders.
        outline: AppColors.textMutedOnDark,
        outlineVariant: AppColors.surfaceDark,
        surfaceContainerHigh: AppColors.surfaceDark,
        surfaceContainerLowest: AppColors.backgroundDark,
      ),
    );
    return base.copyWith(
      // Dark-surface ink — see AppTypography.themeFor.
      textTheme: AppTypography.themeFor(Brightness.dark),
      scaffoldBackgroundColor: AppColors.backgroundDark,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surfaceDark,
        foregroundColor: AppColors.darkTextOnDark,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: AppColors.darkTextOnDark),
        titleTextStyle: AppTypography.headingMedium.copyWith(
          color: AppColors.darkTextOnDark,
        ),
      ),
      cardTheme: AppCardStyles.standard.copyWith(color: AppColors.surfaceDark),
      filledButtonTheme: FilledButtonThemeData(style: AppButtonStyles.filled),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: AppButtonStyles.elevated,
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: AppButtonStyles.outlined,
      ),
      textButtonTheme: TextButtonThemeData(style: AppButtonStyles.text),
      inputDecorationTheme: AppInputStyles.theme,
    );
  }
}
