/// Centralized input-decoration styles — the SINGLE source of truth for all
/// `InputDecorationTheme` / `InputDecoration` definitions in the app.
library;
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radius.dart';

abstract final class AppInputStyles {
  AppInputStyles._();

  static const double fieldHeight = 46.0;
  static const double fieldHeightSm = 36.0;

  static InputDecorationTheme get theme {
    return InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: AppColors.lightGray,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 10,
      ),
      border: const OutlineInputBorder(
        borderSide: BorderSide.none,
        borderRadius: AppRadius.mdBorder,
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: AppColors.borderGray, width: 1),
        borderRadius: AppRadius.mdBorder,
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
        borderRadius: AppRadius.mdBorder,
      ),
      errorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: AppColors.error, width: 1),
        borderRadius: AppRadius.mdBorder,
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: AppColors.error, width: 2),
        borderRadius: AppRadius.mdBorder,
      ),
      hintStyle: const TextStyle(
        color: AppColors.textMuted,
        fontSize: 14,
      ),
      labelStyle: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 13,
      ),
      errorStyle: const TextStyle(
        color: AppColors.error,
        fontSize: 11,
        height: 1.4,
      ),
      counterStyle: TextStyle(
        color: AppColors.textMuted,
        fontSize: 12,
      ),
    );
  }
}
