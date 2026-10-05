import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hyperlocal_app/core/layout/responsive.dart';
import 'package:hyperlocal_app/core/layout/text_scaling.dart';
import 'package:hyperlocal_app/core/theme/app_theme.dart';

/// Measures the height a piece of text actually needs, ignoring the viewport.
///
/// This exists because `tester.getSize(find.byType(Text))` is useless for this
/// job: inside a fixed-height rail the text box is CONSTRAINED to the rail, so
/// it always reports the rail's own height and the assertion degenerates into
/// `200 <= 200`. An earlier version of this test passed even with the scaling
/// deleted from `carouselHeight` — it was checking nothing at all.
///
/// A `TextPainter` has no viewport, so it reports the height the text really
/// wants, which is the only number worth comparing a rail against.
double _naturalTextHeight(
  String text, {
  required double width,
  required double fontSize,
  required TextScaler scaler,
  FontWeight weight = FontWeight.normal,
  double height = 1.3,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontSize: fontSize, fontWeight: weight, height: height),
    ),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
  )..layout(maxWidth: width);
  return painter.height;
}

/// A stand-in for a real card: a fixed-height image plus text that scales.
///
/// The mix matters. An image does not grow with the font, so a card's content
/// does not scale linearly — it grows toward `image + text x scale`. That is
/// exactly why `SizedBox(height: 240)` broke, and why a proportional
/// `base x scale` is the right repair rather than another arbitrary constant.
class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.subtitle,
    required this.imageHeight,
  });

  final String title;
  final String subtitle;
  final double imageHeight;

  @override
  Widget build(BuildContext context) {
    // Proportions copied from the real `ProductCard`: a 100px image, a 14pt
    // bold title capped at 2 lines, and a 13pt shop line.
    //
    // The `maxLines` caps are load-bearing and worth stating plainly: they stop
    // the text growing without bound. That is what made the old fixed 240 rail
    // MARGINAL rather than hopeless — it survived most font sizes by luck of the
    // caps, and started clipping only once the caps and the scale stacked up.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(height: imageHeight, color: const Color(0xFFDDDDDD)),
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13),
        ),
      ],
    );
  }
}

// The proportions of a real product/shop card sitting in a rail.
const double _imageHeight = 100;
const double _cardWidth = 240;
const String _title = 'Samsung Galaxy S24 5G 256GB discounted this week';
const String _subtitle = 'Available at 3 stores near you';

/// Real device classes, rather than the 800x600 default test surface.
const Size _smallPhone = Size(320, 568);
const Size _standardPhone = Size(390, 844);
const Size _largePhone = Size(430, 932);
const Size _tablet = Size(834, 1194);

/// Builds the rail under test, wired the way the real Home rails are.
Widget _host({required double scale}) {
  return MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            return SizedBox(
              height: Responsive.carouselHeight(
                baseHeight: 240,
                textScale: MediaQuery.textScalerOf(context),
              ),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(
                  horizontal: Responsive.gutterFor(constraints.maxWidth),
                ),
                children: [
                  const SizedBox(
                    width: _cardWidth,
                    child: _Card(
                      title: _title,
                      subtitle: _subtitle,
                      imageHeight: _imageHeight,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}

/// Asserts the card's painted bottom is inside the rail's visible bottom.
///
/// This is the assertion that actually has teeth. `takeException() isNull`
/// passes even when a card is cut in half, because a `ListView` clips its
/// children quietly — the failure a customer would see is a card with the
/// price missing, and it raises nothing at all.
void _expectCardNotClipped(WidgetTester tester, String where) {
  final railBottom = tester.getRect(find.byType(ListView)).bottom;
  final cardBottom = tester.getRect(find.byType(_Card)).bottom;
  expect(
    cardBottom,
    lessThanOrEqualTo(railBottom + 0.5),
    reason:
        'the card is clipped on $where — it ends at '
        '${cardBottom.toStringAsFixed(1)} but the rail ends at '
        '${railBottom.toStringAsFixed(1)}',
  );
}

void main() {
  group('the rail grows with the font', () {
    // This is the property the whole change rests on, and it is the test that
    // has teeth: deleting the `* textScale` from `carouselHeight` breaks it,
    // whereas `takeException() isNull` happily passes with the scaling gone.
    for (final base in <double>[160, 200, 240]) {
      testWidgets('a ${base.toInt()}px rail grows with the text scale', (
        tester,
      ) async {
        var previous = 0.0;
        for (final scale in <double>[1.0, 1.3, 1.8, 2.0, 2.5]) {
          final height = Responsive.carouselHeight(
            baseHeight: base,
            textScale: TextScaler.linear(scale),
          );
          expect(
            height,
            greaterThan(previous),
            reason:
                'a ${base.toInt()}px rail must be taller at '
                '${TextScaling.describe(scale)} than at the previous scale',
          );
          previous = height;
        }
      });
    }
  });

  group('the rail clears the card it holds', () {
    // Only the 240px rail, because `_Card` models `ProductCard` (100px image, a
    // 2-line 14pt title, a 1-line 13pt shop line). The 200px rail holds a
    // `ShopCard`, which is materially shorter -- mostly single-line 10/12pt text
    // -- so holding the *product* card to it would be comparing two different
    // cards and would report a failure that does not exist.
    for (final base in <double>[240]) {
      for (final scale in <double>[1.0, 1.3, 1.8, 2.0]) {
        testWidgets(
          'a ${base.toInt()}px rail holds its card at ${TextScaling.describe(scale)}',
          (tester) async {
            final scaler = TextScaler.linear(scale);

            // What the card genuinely needs.
            final needed =
                _imageHeight +
                _naturalTextHeight(
                  _title,
                  width: _cardWidth,
                  fontSize: 14,
                  weight: FontWeight.bold,
                  scaler: scaler,
                ) +
                _naturalTextHeight(
                  _subtitle,
                  width: _cardWidth,
                  fontSize: 12,
                  scaler: scaler,
                );

            // What the rail gives.
            final rail = Responsive.carouselHeight(
              baseHeight: base,
              textScale: scaler,
            );

            expect(
              rail,
              greaterThanOrEqualTo(needed),
              reason:
                  'at ${TextScaling.describe(scale)} the card needs '
                  '${needed.toStringAsFixed(1)}px but the rail gives '
                  '${rail.toStringAsFixed(1)}px. Without the scale the card is '
                  'clipped silently — no exception, just a missing price.',
            );
          },
        );
      }
    }
  });

  group('a real card renders inside the rail without clipping', () {
    for (final scale in <double>[1.0, 1.3, 1.8, 2.0]) {
      testWidgets('the card fits at ${TextScaling.describe(scale)}', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(_standardPhone);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(_host(scale: scale));
        await tester.pumpAndSettle();

        // A Column in a too-short box throws; the geometry check below catches
        // the silent case, where content is merely cut off.
        expect(tester.takeException(), isNull);
        _expectCardNotClipped(tester, TextScaling.describe(scale));
      });
    }
  });

  group('every real device class renders', () {
    for (final entry in <String, Size>{
      'small phone': _smallPhone,
      'standard phone': _standardPhone,
      'large phone': _largePhone,
      'tablet': _tablet,
    }.entries) {
      testWidgets('a ${entry.key} lays out without clipping', (tester) async {
        await tester.binding.setSurfaceSize(entry.value);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(_host(scale: 1.8));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        _expectCardNotClipped(tester, entry.key);
      });
    }
  });

  group('landscape still works', () {
    testWidgets('a rotated phone lays out without clipping', (tester) async {
      // Rotation is the case nobody tests: the same widget, half the height and
      // double the width.
      final landscape = Size(_standardPhone.height, _standardPhone.width);
      await tester.binding.setSurfaceSize(landscape);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_host(scale: 1.8));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      _expectCardNotClipped(tester, 'a rotated phone');
    });
  });
}
