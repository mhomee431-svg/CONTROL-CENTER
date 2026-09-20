import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/ui/text_scale.dart';

/// Responsiveness — font scaling.
///
/// The platform font-size setting is a user right, but the app has to stay
/// laid out: dense stock/price tables need a readability floor, and the boxes
/// with a design height (CTA buttons, chips) define the ceiling. These tests
/// pin both ends and prove that descendants actually see the clamped value
/// (i.e. the policy is applied at the root, not merely defined).
void main() {
  group('TextScalePolicy.clamp', () {
    test('keeps scales already inside the supported band', () {
      expect(TextScalePolicy.clamp(1.0), 1.0);
      expect(
        TextScalePolicy.clamp(TextScalePolicy.minScaleFactor),
        TextScalePolicy.minScaleFactor,
      );
      expect(
        TextScalePolicy.clamp(TextScalePolicy.maxScaleFactor),
        TextScalePolicy.maxScaleFactor,
      );
    });

    test('caps scales above the ceiling (Android Large / Largest / Huge)', () {
      expect(TextScalePolicy.clamp(1.5), TextScalePolicy.maxScaleFactor);
      expect(TextScalePolicy.clamp(2.0), TextScalePolicy.maxScaleFactor);
      expect(TextScalePolicy.clamp(4.0), TextScalePolicy.maxScaleFactor);
    });

    test('raises scales below the readability floor', () {
      expect(TextScalePolicy.clamp(0.8), TextScalePolicy.minScaleFactor);
      expect(TextScalePolicy.clamp(0.5), TextScalePolicy.minScaleFactor);
    });

    test('falls back to 1.0 for invalid platform values', () {
      expect(TextScalePolicy.clamp(double.nan), 1.0);
      expect(TextScalePolicy.clamp(0), 1.0);
      expect(TextScalePolicy.clamp(-1.5), 1.0);
    });
  });

  group('TextScalePolicy.apply', () {
    /// Pumps a 10pt probe under [scale] and returns the size descendants see.
    Future<double> probeFontSize(WidgetTester tester, double scale) async {
      late double scaled;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: TextScalePolicy.apply(
              Builder(
                builder: (context) {
                  scaled = MediaQuery.of(context).textScaler.scale(10);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
      return scaled;
    }

    testWidgets('caps the scale descendants actually see', (tester) async {
      // 10pt at a 2.0 platform scale would be 20pt; the ceiling is 1.3 → 13pt.
      expect(await probeFontSize(tester, 2.0), 13.0);
    });

    testWidgets('honours a platform scale inside the band', (tester) async {
      expect(await probeFontSize(tester, 1.2), closeTo(12.0, 0.001));
    });

    testWidgets('raises a too-small platform scale to the floor',
        (tester) async {
      expect(await probeFontSize(tester, 0.5), closeTo(8.5, 0.001));
    });
  });
}
