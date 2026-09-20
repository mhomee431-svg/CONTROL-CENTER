import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/theme/app_theme.dart';
import 'package:hyperlocal_shopkeeper_app/core/theme/app_typography.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_models.dart';

/// Accessibility — "adequate contrast" and "readable text" (WCAG 2.1 AA).
///
/// Regression guards for three defects found by inspecting theme tokens rather
/// than by eye:
///
///   1. `scheme.outline` carried the *border* token (#E2E8F0, ~1.2:1 on white)
///      while 148 call sites use it as a **text** colour — meta text
///      (timestamps, SKUs, captions) was effectively unreadable in light mode.
///   2. `AppTypography.caption` used `textDisabled` (#94A3B8, 2.9:1) — below
///      the 4.5:1 AA threshold for normal text.
///   3. `dark()` reused a colourless, font-only text theme, which strips
///      Material's brightness-aware ink.
///
/// Maths follows WCAG 2.1 §1.4.3/1.4.11 (4.5:1 normal text, 3:1 large text and
/// UI-component boundaries).

double _channel(double v) =>
    v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

/// WCAG contrast ratio between two opaque colours.
double contrastRatio(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('light theme contrast', () {
    final theme = AppTheme.light();

    test('outline — used as meta text and input borders — passes AA', () {
      expect(
        contrastRatio(theme.colorScheme.outline, theme.colorScheme.surface),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('body ink passes AA on the surface', () {
      final ink = theme.textTheme.bodyMedium?.color;
      expect(ink, isNotNull, reason: 'body ink must be resolved, not inherited');
      expect(
        contrastRatio(ink!, theme.colorScheme.surface),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('body ink passes AA on the scaffold background', () {
      final ink = theme.textTheme.bodyMedium!.color!;
      expect(
        contrastRatio(ink, theme.scaffoldBackgroundColor),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('strong ink passes AAA', () {
      final ink = theme.textTheme.titleMedium?.color;
      expect(ink, isNotNull);
      expect(
        contrastRatio(ink!, theme.colorScheme.surface),
        greaterThanOrEqualTo(7),
      );
    });
  });

  group('dark theme contrast', () {
    final theme = AppTheme.dark();

    test('outline — used as meta text and input borders — passes AA', () {
      expect(
        contrastRatio(theme.colorScheme.outline, theme.colorScheme.surface),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('body ink is bright ink, not the painter-default black', () {
      final ink = theme.textTheme.bodyMedium?.color;
      expect(ink, isNotNull, reason: 'body ink must be resolved, not inherited');
      expect(
        contrastRatio(ink!, theme.colorScheme.surface),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('strong ink passes AAA', () {
      final ink = theme.textTheme.titleMedium?.color;
      expect(ink, isNotNull);
      expect(
        contrastRatio(ink!, theme.colorScheme.surface),
        greaterThanOrEqualTo(7),
      );
    });
  });

  group('typography tokens', () {
    test('the caption style does not hard-code a sub-AA ink', () {
      // Colourless by design: it must inherit the resolved, brightness-aware
      // ink instead of pinning the light-only #94A3B8.
      expect(AppTypography.caption.color, isNull);
    });

    test('themeFor resolves ink for both brightnesses', () {
      for (final brightness in Brightness.values) {
        final textTheme = AppTypography.themeFor(brightness);
        expect(textTheme.bodyMedium?.color, isNotNull,
            reason: '$brightness bodyMedium');
        expect(textTheme.titleMedium?.color, isNotNull,
            reason: '$brightness titleMedium');
      }
    });

    test('every enabled text slot is AA against its surface', () {
      // The requirement is contrast, not token identity — two tokens may share
      // a hex value (textMutedOnDark == textDisabled == #94A3B8) and still be
      // correct, because what matters is the ratio on the surface it renders on.
      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        final surface = theme.colorScheme.surface;
        final slots = {
          'bodyLarge': theme.textTheme.bodyLarge,
          'bodyMedium': theme.textTheme.bodyMedium,
          'titleMedium': theme.textTheme.titleMedium,
          'labelLarge': theme.textTheme.labelLarge,
          'labelSmall': theme.textTheme.labelSmall,
        };
        slots.forEach((name, style) {
          final colour = style?.color;
          expect(colour, isNotNull,
              reason: '$name in ${theme.brightness} must resolve');
          expect(
            contrastRatio(colour!, surface),
            greaterThanOrEqualTo(4.5),
            reason: '$name in ${theme.brightness}',
          );
        });
      }
    });
  });

  group('rendered text resolves to readable ink', () {
    for (final entry
        in [('light', AppTheme.light()), ('dark', AppTheme.dark())]) {
      testWidgets('${entry.$1}: the inherited ink meets AA', (tester) async {
        Color? ink;
        Color? background;
        await tester.pumpWidget(
          MaterialApp(
            theme: entry.$2,
            // The Scaffold/Material is what installs the theme's body ink as
            // the inherited DefaultTextStyle, so the probe must live inside it
            // — outside, Flutter falls back to WidgetsApp's red error style.
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  // What a plain `Text` with no explicit colour would inherit.
                  ink = DefaultTextStyle.of(context).style.color;
                  background = Theme.of(context).scaffoldBackgroundColor;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        expect(ink, isNotNull,
            reason: 'an unresolved ink falls back to black, breaking dark mode');
        expect(contrastRatio(ink!, background!), greaterThanOrEqualTo(4.5));
      });
    }
  });

  group('status is never colour-only', () {
    test('every stock state exposes a text label', () {
      // The UI renders `label` beside the colour chip, so "Low Stock" stays
      // readable without relying on red/amber alone.
      for (final raw in [
        'IN_STOCK',
        'LOW_STOCK',
        'OUT_OF_STOCK',
        'UNKNOWN',
        'DISCONTINUED',
      ]) {
        expect(StockStateView.of(raw).label.trim(), isNotEmpty, reason: raw);
      }
    });
  });
}
