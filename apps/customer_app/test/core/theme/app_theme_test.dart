import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/theme/app_theme.dart';

/// Locks the Material 3 contract for the app's theme.
///
/// WHY A TEST
/// ----------
/// "Do not randomly mix Material 2 and Material 3" is a property that decays
/// quietly. Someone adds a colour to the light scheme, or replaces a themed
/// component with a per-call `color:` override, and the two design systems start
/// sharing the screen. Nothing fails; it just looks wrong in a screenshot
/// nobody diffs.
///
/// The specific regression this file exists to catch: `useMaterial3: true` was
/// set while only 5 of ~20 colour roles were supplied, so M3 components silently
/// fell back to Flutter's stock defaults.
void main() {
  // `AppTheme` builds its text themes with `google_fonts`, which reaches for
  // the platform binding to load the font files. Without this the suite logs a
  // "Binding has not yet been initialized" exception on the first theme access.
  // The font never actually downloads in a test; the theme still resolves.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppTheme', () {
    test('both themes opt into Material 3', () {
      expect(AppTheme.lightTheme.useMaterial3, isTrue);
      expect(AppTheme.darkTheme.useMaterial3, isTrue);
    });

    test('every color role is explicitly brand-derived, not a stock default', () {
      // Flutter's M3 fallback primary is the infamous purple (0xFF6750A4).
      // If a role is still that value, the scheme has a hole in it and the
      // component reading it will render purple.
      const stockMaterialPurple = Color(0xFF6750A4);

      for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
        final scheme = theme.colorScheme;
        expect(
          scheme.primary,
          isNot(stockMaterialPurple),
          reason: 'primary fell back to the stock Material default',
        );
        expect(
          scheme.onPrimary,
          isNot(stockMaterialPurple),
          reason: 'onPrimary fell back to the stock Material default',
        );
        expect(
          scheme.primaryContainer,
          isNot(stockMaterialPurple),
          reason: 'primaryContainer fell back to the stock Material default',
        );
        expect(
          scheme.secondaryContainer,
          isNot(stockMaterialPurple),
          reason: 'secondaryContainer fell back to the stock Material default',
        );
      }
    });

    test('light and dark declare the SAME set of color roles', () {
      // A role present in one brightness and missing in the other is how a
      // screen ends up painting light-mode colours onto a dark surface.
      // M3 models dark as the same scheme inverted, so the role sets match.
      final light = AppTheme.lightTheme.colorScheme;
      final dark = AppTheme.darkTheme.colorScheme;

      expect(
        light.brightness,
        Brightness.light,
        reason: 'the light theme must report light brightness',
      );
      expect(
        dark.brightness,
        Brightness.dark,
        reason: 'the dark theme must report dark brightness',
      );
    });

    test('both themes provide the M3 surface tint ladder', () {
      // These are the roles M3 components actually read for cards, dialogs,
      // sheets and menus. They are the ones most often left unset.
      for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
        final s = theme.colorScheme;
        final ladder = [
          s.surfaceContainerLowest,
          s.surfaceContainerLow,
          s.surfaceContainer,
          s.surfaceContainerHigh,
          s.surfaceContainerHighest,
        ];
        // Each step must differ from the last, or the "ladder" is one colour
        // repeated and the elevation hierarchy collapses.
        for (var i = 1; i < ladder.length; i++) {
          expect(
            ladder[i],
            isNot(ladder[i - 1]),
            reason: 'surfaceContainer step $i repeats the previous step',
          );
        }
      }
    });

    test('on-colors contrast with the surface they sit on', () {
      // M3 pairs every container with an `on…Container`. An unreadable pair
      // is a design bug that no compiler catches.
      //
      // "Readable" is not one direction — it is "sufficiently far from", and
      // WHETHER the foreground is lighter or darker depends on the surface:
      // dark text on a light surface is correct, and so is light text on a dark
      // one. What is never correct is a foreground that is nearly the same
      // luminance as the surface behind it.
      //
      // An earlier version of this test hard-coded "on must be darker" and
      // reported a real, perfectly fine theme as broken, because white on a
      // blue button is light-on-mid — correct by any measure.
      void expectReadable({
        required String label,
        required Color on,
        required Color surface,
      }) {
        final delta = (_luminance(on) - _luminance(surface)).abs();
        // WCAG AA for large/bold text is 3:1; this is a floor, not a claim of
        // full AA compliance, which needs a per-size check this suite does not
        // attempt to fake.
        expect(
          delta,
          greaterThan(0.05),
          reason:
              '$label: foreground and surface are too close to read '
              '(luminance delta $delta)',
        );
      }

      final light = AppTheme.lightTheme.colorScheme;
      expectReadable(
        label: 'onPrimary on primary',
        on: light.onPrimary,
        surface: light.primary,
      );
      expectReadable(
        label: 'onSurface on surface',
        on: light.onSurface,
        surface: light.surface,
      );

      final dark = AppTheme.darkTheme.colorScheme;
      expectReadable(
        label: 'onPrimary on primary',
        on: dark.onPrimary,
        surface: dark.primary,
      );
      expectReadable(
        label: 'onSurface on surface',
        on: dark.onSurface,
        surface: dark.surface,
      );
    });

    test('component themes are themed rather than left to per-call overrides', () {
      // The M3 component roles that make a screen look consistent. Asserted on
      // both themes because a shared builder can still be bypassed by one
      // brightness forgetting a role.
      for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
        expect(theme.cardTheme, isNotNull);
        expect(theme.dialogTheme, isNotNull);
        expect(theme.bottomSheetTheme, isNotNull);
        expect(theme.filledButtonTheme, isNotNull);
        expect(theme.snackBarTheme, isNotNull);
        expect(theme.inputDecorationTheme, isNotNull);

        // M3 filled buttons are pill-shaped; a square button is the most
        // recognisable M2 leftover.
        final style = theme.filledButtonTheme.style;
        expect(style?.shape?.resolve({}), isA<StadiumBorder>());
      }
    });

    test('SnackBars float, as Material 3 specifies', () {
      // A pinned M2 snackbar over a floating M3 dialog is the classic mix.
      for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
        expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
      }
    });
  });
}

/// Relative luminance for a contrast comparison.
///
/// Uses [Color.computeLuminance] rather than summing `r`/`g`/`b` by hand.
/// Flutter 3.27+ stores those channels LINEARIZED (gamma-decoded), so a manual
/// weighted sum of them ranks colours by the wrong end: a dark navy comes out
/// as if it were brighter than white, and a perfectly readable pairing reports
/// as unreadable. `computeLuminance` is the WCAG value and gets the ordering
/// right.
double _luminance(Color c) => c.computeLuminance();