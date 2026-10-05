/// Centralized button styles -- the SINGLE source of truth for all
/// ButtonStyle definitions in the app.
library;

import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radius.dart';
import 'app_shadows.dart';

abstract final class AppButtonStyles {
  AppButtonStyles._();

  static const double primaryHeight = 46.0;
  static const double secondaryHeight = 46.0;
  static const double smallHeight = 32.0;
  static const double iconSize = 18.0;

  // -- Filled (the app's actual primary) ------------------------------
  //
  // THIS is the style that matters: the codebase renders `FilledButton` in 79
  // places and `ElevatedButton` in **zero**. Wiring the brand style to
  // `elevatedButtonTheme` alone (as this file previously did) therefore styled
  // a button nobody uses, and every real CTA fell back to the M3 default — a
  // 48dp **stadium/pill** shape at full width instead of the 12dp rounded
  // rectangle the design contract calls for. `filled` and `elevated` are
  // therefore deliberately the same token set; `elevated` stays for the rare
  // raised surface but is no longer the primary's home.
  static final ButtonStyle filled = FilledButton.styleFrom(
    backgroundColor: AppColors.primary,
    foregroundColor: AppColors.onPrimary,
    minimumSize: Size(0, primaryHeight),
    shape: RoundedRectangleBorder(borderRadius: AppRadius.mdBorder),
    elevation: AppShadows.elevationNone, // flat: the radius carries the shape
    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
  );

  // -- Elevated (filled) ---------------------------------------------
  static final ButtonStyle elevated = ElevatedButton.styleFrom(
    backgroundColor: AppColors.primary,
    foregroundColor: AppColors.onPrimary,
    minimumSize: Size(0, primaryHeight),
    shape: RoundedRectangleBorder(borderRadius: AppRadius.mdBorder),
    elevation: AppShadows.elevationLg,
    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
  );

  // -- Outlined -----------------------------------------------------
  static final ButtonStyle outlined = OutlinedButton.styleFrom(
    foregroundColor: AppColors.primary,
    minimumSize: Size(0, secondaryHeight),
    shape: RoundedRectangleBorder(borderRadius: AppRadius.mdBorder),
    side: const BorderSide(color: AppColors.primary),
    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
  );

  // -- Text ---------------------------------------------------------
  static final ButtonStyle text = TextButton.styleFrom(
    foregroundColor: AppColors.primary,
    // No minimumSize: TextButtons are inline and must not force width.
    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
  );

  // -- Destructive (error) ------------------------------------------
  static final ButtonStyle destructive = ElevatedButton.styleFrom(
    backgroundColor: AppColors.error,
    foregroundColor: AppColors.white,
    minimumSize: Size(0, primaryHeight),
    shape: RoundedRectangleBorder(borderRadius: AppRadius.mdBorder),
    elevation: AppShadows.elevationLg,
    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
  );
}
