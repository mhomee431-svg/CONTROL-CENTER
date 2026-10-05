import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hyperlocal_app/core/layout/responsive.dart';
import 'package:hyperlocal_app/core/layout/text_scaling.dart';

/// Guards the responsive rules.
///
/// These assert behaviour at REAL device sizes rather than only the default
/// 800x600 test surface, because the default window is not a phone and will
/// happily pass a layout that overflows on every actual handset.
void main() {
  // Representative logical sizes. Small-first, because the small phone is the
  // tightest constraint and the one most likely to expose a fixed size.
  const smallPhone = Size(320, 568); // iPhone SE 1st gen class
  const standardPhone = Size(390, 844); // iPhone 14 class
  const largePhone = Size(430, 932); // Pro Max class
  const tabletPortrait = Size(834, 1194); // iPad class
  const tabletLandscape = Size(1194, 834);

  group('width classes', () {
    test('a small phone is compact', () {
      expect(Responsive.widthClassFor(smallPhone.width), WidthClass.compact);
    });

    test('a large phone is still not a tablet', () {
      // The distinction matters: a 430dp phone must NOT get a two-column
      // layout, because two 200dp cards side by side do not fit in 430dp.
      expect(Responsive.widthClassFor(largePhone.width), WidthClass.compact);
    });

    test('a tablet portrait is expanded', () {
      expect(
        Responsive.widthClassFor(tabletPortrait.width),
        WidthClass.expanded,
      );
    });

    test('a landscape tablet is large', () {
      expect(Responsive.widthClassFor(tabletLandscape.width), WidthClass.large);
    });

    test('the boundary values themselves land in the right class', () {
      // Off-by-one on a breakpoint is the classic responsive bug: exactly at
      // the boundary must be the WIDER class, not one below it.
      expect(
        Responsive.widthClassFor(Responsive.mediumWidth),
        WidthClass.medium,
      );
      expect(
        Responsive.widthClassFor(Responsive.expandedWidth),
        WidthClass.expanded,
      );
      expect(Responsive.widthClassFor(Responsive.largeWidth), WidthClass.large);
      expect(
        Responsive.widthClassFor(Responsive.mediumWidth - 0.1),
        WidthClass.compact,
      );
    });
  });

  group('height classes and orientation', () {
    test('a landscape phone is short on height', () {
      // Rotating a 844dp-tall phone to landscape leaves ~390dp. Layouts that
      // assume vertical room break here, and this is the case that gets missed
      // because nobody tests landscape.
      expect(Responsive.heightClassFor(smallPhone.height), HeightClass.tall);
      expect(Responsive.heightClassFor(390), HeightClass.short);
    });

    test('rotating a phone responds to the new width', () {
      final portrait = Responsive.widthClassFor(largePhone.width);
      expect(portrait, WidthClass.compact);

      // After rotation the former HEIGHT is the width: 932dp of horizontal
      // room. Two columns genuinely fit there, so classing it as a tablet-ish
      // layout is correct — this test asserts the layout FOLLOWS the rotation
      // rather than freezing, which is the failure mode being guarded.
      final rotated = Responsive.widthClassFor(largePhone.height);
      expect(rotated, isNot(portrait));
      expect(rotated, WidthClass.expanded);
    });

    test('a landscape phone is short on height after rotation', () {
      // The height class is what governs "can I afford to stack vertically".
      // Rotated a Pro Max is 430 tall, which is the case that gets missed.
      expect(Responsive.heightClassFor(standardPhone.height), HeightClass.tall);
      expect(Responsive.heightClassFor(standardPhone.width), HeightClass.short);
    });
  });

  group('gutter', () {
    test('grows with width so lines never run too long', () {
      expect(
        Responsive.gutterFor(smallPhone.width),
        lessThan(Responsive.gutterFor(tabletLandscape.width)),
      );
    });

    test('is never zero or negative on any size', () {
      for (final width in [280.0, 320.0, 390.0, 834.0, 1440.0]) {
        expect(Responsive.gutterFor(width), greaterThan(0));
      }
    });
  });

  group('grid columns', () {
    test('a phone gets one column of realistic cards', () {
      expect(Responsive.columnsFor(width: smallPhone.width, itemWidth: 180), 1);
    });

    test('a tablet fits more than one', () {
      final cols = Responsive.columnsFor(
        width: tabletPortrait.width,
        itemWidth: 180,
      );
      expect(cols, greaterThan(1));
    });

    test('never returns zero, however narrow', () {
      // A zero or negative count is a crash in GridView, and 280dp is a real
      // split-screen width, not a hypothetical.
      expect(Responsive.columnsFor(width: 280, itemWidth: 180), 1);
      expect(Responsive.columnsFor(width: 100, itemWidth: 180), 1);
    });

    test('a nonsensical item width cannot divide by zero', () {
      expect(
        Responsive.columnsFor(width: tabletPortrait.width, itemWidth: 0),
        1,
      );
    });
  });

  group('carousel height', () {
    test('at the default text scale it is the base height', () {
      expect(
        Responsive.carouselHeight(
          baseHeight: 200,
          textScale: TextScaler.noScaling,
        ),
        200,
      );
    });

    test('it GROWS with the system text scale', () {
      // This is the whole point. A fixed height means the card grows with the
      // text while its container does not, and the row overflows for anyone
      // running an accessibility font size.
      final at2x = Responsive.carouselHeight(
        baseHeight: 200,
        textScale: const TextScaler.linear(2.0),
      );
      expect(at2x, greaterThan(200));
    });

    test('it is capped so an extreme scale cannot make a giant rail', () {
      // At 4x a 200dp base would be 800dp -- taller than the viewport, and the
      // content would be scrolled out of sight inside the rail.
      //
      // The cap is proportional to the base, not an absolute 420. An absolute
      // cap froze a 240dp rail at 420 from 1.75x upward, so above that point the
      // rail stopped growing while its card did not -- reintroducing the very
      // clipping the cap was meant to bound.
      final at4x = Responsive.carouselHeight(
        baseHeight: 200,
        textScale: const TextScaler.linear(4.0),
      );
      expect(at4x, 500.0); // 200 * the 2.5x clamp
    });

    test('it keeps growing all the way to the 2.5x app-wide clamp', () {
      // The global clamp lets a customer reach 2.5x, so the rail must still be
      // responding at that end of the range -- not flat from some earlier point.
      var previous = 0.0;
      for (final scale in <double>[1.0, 1.3, 1.8, 2.0, 2.3, 2.5]) {
        final height = Responsive.carouselHeight(
          baseHeight: 240,
          textScale: TextScaler.linear(scale),
        );
        expect(
          height,
          greaterThan(previous),
          reason: 'the rail stopped growing by ${TextScaling.describe(scale)}',
        );
        previous = height;
      }
    });
  });

  group('readableWidth', () {
    testWidgets('caps and centres on a tablet', (tester) async {
      await tester.binding.setSurfaceSize(tabletLandscape);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Responsive.readableWidth(child: const Text('content')),
          ),
        ),
      );

      final width = tester.getSize(find.text('content')).width;
      expect(width, lessThanOrEqualTo(Responsive.maxReadableWidth));
    });

    test('the cap never binds on a phone', () {
      // Sanity: the constraint must not clip anything at handset widths, which
      // is why it is generous enough never to bind there.
      expect(Responsive.maxReadableWidth, greaterThan(largePhone.width));
    });
  });
}
