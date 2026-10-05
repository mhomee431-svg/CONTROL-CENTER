import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hyperlocal_app/core/a11y/contrast.dart';
import 'package:hyperlocal_app/core/theme/app_theme.dart';
import 'package:hyperlocal_app/core/widgets/shop_open_closed_badge.dart';

/// Pins every colour that carries TEXT to a measured WCAG AA ratio.
///
/// WHY THIS FILE EXISTS
/// --------------------
/// Contrast is the only accessibility rule that fails *silently*. A 2.15:1
/// "Low Stock" label looks perfectly reasonable in a design review, in
/// screenshots, and to every sighted person on the team — while being
/// effectively unreadable to a customer in bright sunlight or with low vision.
/// Nothing crashes and no other test notices.
///
/// These assertions are computed with the same maths a contrast checker uses,
/// so a token cannot be quietly darkened or lightened past the threshold
/// without this going red.
void main() {
  group('light mode — text on light surfaces', () {
    final surfaces = <String, Color>{
      'white': AppColors.surfaceLight,
      'background': AppColors.backgroundLight,
    };

    void expectAa(String what, Color fg) {
      for (final entry in surfaces.entries) {
        final r = Contrast.ratio(fg, entry.value);
        expect(
          Contrast.passesAa(fg, entry.value),
          isTrue,
          reason:
              '$what on ${entry.key} is ${r.toStringAsFixed(2)}:1, '
              'below the ${Contrast.aaNormal}:1 AA threshold',
        );
      }
    }

    test('body text is AA', () {
      expectAa('body text', AppColors.textLight);
    });

    test('muted metadata is AA', () {
      // This is the tightest token in the palette (4.76:1 on white). It has the
      // least headroom, so it is the one most likely to regress.
      expectAa('muted text', AppColors.textMuted);
    });

    test('primary link text is AA', () {
      expectAa('primary text', AppColors.primaryText);
    });

    test('success status text is AA', () {
      expectAa('success text', AppColors.successText);
    });

    test('warning status text is AA', () {
      // The worst offender before the fix was 2.15:1.
      expectAa('warning text', AppColors.warningText);
    });

    test('error status text is AA', () {
      expectAa('error text', AppColors.errorText);
    });
  });

  group('dark mode — text on dark surfaces', () {
    final surfaces = <String, Color>{
      'surface': AppColors.surfaceDark,
      'background': AppColors.backgroundDark,
    };

    void expectAa(String what, Color fg) {
      for (final entry in surfaces.entries) {
        final r = Contrast.ratio(fg, entry.value);
        expect(
          Contrast.passesAa(fg, entry.value),
          isTrue,
          reason: '$what on dark ${entry.key} is ${r.toStringAsFixed(2)}:1',
        );
      }
    }

    test('body text is AA', () => expectAa('body text', AppColors.textDark));
    test('muted metadata is AA', () {
      expectAa('muted text', AppColors.textMutedDark);
    });
    test('success status text is AA', () {
      expectAa('success text', AppColors.successTextDark);
    });
    test('warning status text is AA', () {
      expectAa('warning text', AppColors.warningTextDark);
    });
    test('error status text is AA', () {
      expectAa('error text', AppColors.errorTextDark);
    });
  });

  group('the vivid status colours are documented as fill-only', () {
    // These are NOT expected to pass as text — that is the point. This test
    // exists so the reason is written down in executable form: if someone later
    // "fixes" a failing badge by swapping back to [AppColors.warning] as a text
    // colour, the failure message explains why that is the wrong direction.
    test(
      'warning as text on white fails AA, which is why *Text tokens exist',
      () {
        expect(
          Contrast.passesAa(AppColors.warning, AppColors.surfaceLight),
          isFalse,
          reason:
              'vivid warning is for FILLS and ICONS; use AppColors.warningText',
        );
      },
    );

    test('success as text on white fails AA', () {
      expect(
        Contrast.passesAa(AppColors.success, AppColors.surfaceLight),
        isFalse,
        reason:
            'vivid success is for FILLS and ICONS; use AppColors.successText',
      );
    });

    test('error as text on white fails AA', () {
      expect(
        Contrast.passesAa(AppColors.error, AppColors.surfaceLight),
        isFalse,
        reason: 'vivid error is for FILLS and ICONS; use AppColors.errorText',
      );
    });

    test('primaryLight must never carry text', () {
      expect(
        Contrast.passesAa(AppColors.primaryLight, AppColors.surfaceLight),
        isFalse,
        reason:
            'primaryLight is a gradient highlight; use AppColors.primaryText',
      );
    });
  });

  group('rendered status text meets AA', () {
    // The token tests above prove the PALETTE is sound. These prove the WIDGETS
    // actually use the accessible tokens — a token can be perfect while the
    // screen still reaches for the vivid one, which is exactly the mistake this
    // guards. Rendering and reading the style back is the only version of this
    // assertion that reflects what a customer sees.
    Future<Color> textColorOf(
      WidgetTester tester,
      String label,
      Widget widget,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(body: widget),
        ),
      );
      await tester.pumpAndSettle();
      final text = tester.widget<Text>(find.text(label));
      final style =
          text.style ??
          DefaultTextStyle.of(tester.element(find.text(label))).style;
      return style.color ?? AppColors.textLight;
    }

    testWidgets('the badge label passes AA on a card background', (
      tester,
    ) async {
      // The chip paints a 12%-alpha tint of the vivid colour, so the effective
      // background is very close to the surface — the ratio is checked against
      // the real surface the card sits on.
      for (final entry in <String, ({bool open, bool? accepting})>{
        'Open': (open: true, accepting: null),
        'Closed': (open: false, accepting: null),
        'Open · No orders': (open: true, accepting: false),
      }.entries) {
        final color = await textColorOf(
          tester,
          entry.key,
          ShopOpenClosedBadge(
            isOpenNow: entry.value.open,
            acceptingOrders: entry.value.accepting,
          ),
        );
        expect(
          Contrast.passesAa(color, AppColors.surfaceLight),
          isTrue,
          reason:
              'the "${entry.key}" label is ${Contrast.ratio(color, AppColors.surfaceLight).toStringAsFixed(2)}:1',
        );
      }
    });
  });

  group('the maths itself', () {
    test('black on white is the 21:1 maximum', () {
      expect(Contrast.ratio(Colors.black, Colors.white), closeTo(21.0, 0.01));
    });

    test('a colour against itself is 1:1', () {
      expect(
        Contrast.ratio(AppColors.primary, AppColors.primary),
        closeTo(1.0, 0.01),
      );
    });

    test('the ratio is order-independent', () {
      final a = Contrast.ratio(AppColors.textLight, AppColors.surfaceLight);
      final b = Contrast.ratio(AppColors.surfaceLight, AppColors.textLight);
      expect(a, closeTo(b, 0.0001));
    });
  });
}
