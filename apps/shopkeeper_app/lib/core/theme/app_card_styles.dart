/// Centralized card styles — the SINGLE source of truth for all
/// `CardThemeData` definitions in the app.
library;
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radius.dart';
import 'app_shadows.dart';

abstract final class AppCardStyles {
  AppCardStyles._();

  // ── Standard card (used throughout settings, forms, lists) ────────
  static CardThemeData get standard {
    return CardThemeData(
      elevation: AppShadows.elevationNone,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.mdBorder,
        side: const BorderSide(color: AppColors.borderGray, width: 1),
      ),
      color: AppColors.surface,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
    );
  }

  // ── Elevated card (used for intros, notices, FAB-like surfaces) ──
  static CardThemeData get elevated {
    return CardThemeData(
      elevation: AppShadows.elevationLg,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.mdBorder,
      ),
      color: AppColors.surface,
      shadowColor: const Color(0x1A000000),
      surfaceTintColor: Colors.transparent,
    );
  }

  // ── Flat card (no border, no shadow — used inside surfaces) ───────
  static CardThemeData get flat {
    return CardThemeData(
      elevation: AppShadows.elevationNone,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.mdBorder,
      ),
      color: AppColors.surface,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
    );
  }
}
