/// Centralized color tokens for the HyperLocal Shopkeeper App.
///
/// This is the SINGLE source of truth for every color used in the app.
/// No screen should hardcode a `Color(...)` — reference the token instead.
///
/// Palette (matching the HyperLocal brand reference):
///   Primary:        HyperLocal blue / royal blue
///   Supporting:     Green, Orange, White, Light gray, Dark text
library;

import 'package:flutter/material.dart';

abstract final class AppColors {
  AppColors._();

  // ── Primary: HyperLocal blue / royal blue ─────────────────────────
  /// Primary brand color — royal blue, the app's identity color.
  static const primary = Color(0xFF2563EB);
  static const primaryContainer = Color(0xFF4B82F5);
  static const onPrimary = Colors.white;
  static const primaryFixed = Color(0xFFDBEAFE); // 50-shade tint for surfaces
  static const primaryFixedDim = Color(0xFF93C5FD);

  // ── Supporting — Green (status / success) ─────────────────────────
  static const green = Color(0xFF10B981);
  static const greenLight = Color(0xFFD1FAE5);

  // ── Supporting — Orange (accent / warning highlights) ───────────────
  //
  // Visual-reference role: orange is the warning-highlight / tertiary accent
  // (pending states, promotional badges, attention cues) — never a primary
  // action color. Screens read it via the ColorScheme.tertiary mapping below
  // (see AppTheme) or this token directly; never a hardcoded Color(0x…).
  static const orange = Color(0xFFF59E0B);
  static const orangeLight = Color(0xFFFED7AA);
  static const tertiary = orange;
  static const onTertiary = Colors.white;

  // ── Supporting — White ────────────────────────────────────────────
  static const white = Colors.white;

  // ── Supporting — Light gray (surface / background) ───────────────
  static const lightGray = Color(0xFFF1F5F9);
  static const lighterGray = Color(0xFFF8FAFC);
  static const borderGray = Color(0xFFE2E8F0);
  static const mutedGray = Color(0xFFCBD5E1);

  // ── Supporting — Dark text ────────────────────────────────────────
  static const darkText = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF475569);
  static const textMuted = Color(0xFF64748B);
  static const textDisabled = Color(0xFF94A3B8);

  // ── Status colors (semantic) ──────────────────────────────────────
  static const success = Color(0xFF10B981);
  static const warning = Color(0xFFF59E0B);
  static const error = Color(0xFFEF4444);
  static const errorLight = Color(0xFFFEE2E2);
  static const info = Color(0xFF3B82F6);

  // ── Backgrounds (light theme) ─────────────────────────────────────
  static const background = Color(0xFFF8FAFC);
  static const surface = Colors.white;

  // ── Backgrounds (dark theme) ──────────────────────────────────────
  static const backgroundDark = Color(0xFF0F172A);
  static const surfaceDark = Color(0xFF1E293B);
  static const darkTextOnDark = Color(0xFFF8FAFC);
  static const textMutedOnDark = Color(0xFF94A3B8);

  // ── Overlays (camera preview / full-bleed dark surfaces) ──────────
  /// Solid black backdrop behind camera previews and full-bleed overlays.
  static const overlayBackdrop = Color(0xFF000000);

  /// Primary content drawn on [overlayBackdrop].
  static const onOverlay = Colors.white;

  /// Secondary content on [overlayBackdrop] (white at 70%).
  static const onOverlayMuted = Color(0xB3FFFFFF);

  // ── Google sign-in brand palette (brand-mandated, NOT app palette) ─
  // Required verbatim by the Google Sign-In button guidelines, so these
  // deliberately sit outside the HyperLocal palette. They must never be
  // reused as generic UI colors.
  static const googleBlue = Color(0xFF4285F4);
  static const googleRed = Color(0xFFEA4335);
  static const googleYellow = Color(0xFFFBBC05);
  static const googleGreen = Color(0xFF34A853);

  /// Google button border and label ink, per the same spec.
  static const googleBorder = Color(0xFFDADCE0);
  static const googleInk = Color(0xFF1F1F1F);

  // ── Quality ramp (GPS accuracy tiers, confidence indicators) ───────
  // The palette's own graduated axis: green → orange → red. Every screen
  // that scores a value (accuracy, freshness, match confidence) reads from
  // this ramp so the same score always looks the same.
  static const qualityBest = green;
  static const qualityGood = Color(0xFF22C55E);
  static const qualityFair = orange;
  static const qualityPoor = Color(0xFFEA580C);
  static const qualityBad = error;
  static const qualityUnknown = mutedGray;

  /// Soft primary tint behind small icons / leading avatars (royal blue 10%).
  static const primarySoft = Color(0x1A2563EB);

  // ── Misc ──────────────────────────────────────────────────────────
  /// Fully transparent — used to explicitly drop a divider or border.
  static const transparent = Colors.transparent;

  // ── Shopkeeper-specific status colors (legacy aliases, centralized) ─
  /// Deep commerce green. NB: deliberately NOT the same thing as
  /// `AppTheme.brandSeed`, which is the royal-blue brand identity.
  static const deepGreen = Color(0xFF0B5D3B);

  /// @deprecated Ambiguous — this name is used by [AppTheme.brandSeed] for the
  /// royal-blue brand color, so prefer [deepGreen] here.
  static const brandSeed = deepGreen;
  static const verifiedGreen = Color(0xFF1E8E3E);
  static const pendingAmber = Color(0xFFB26A00);
  static const rejectedRed = Color(0xFFC5221F);
  static const suspendedGrey = Color(0xFF5F6368);
}
