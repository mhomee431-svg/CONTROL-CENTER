import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hyperlocal_app/core/layout/text_scaling.dart';
import 'package:hyperlocal_app/core/theme/app_theme.dart';
import 'package:hyperlocal_app/core/widgets/shop_open_closed_badge.dart';

import 'text_scale_sweep.dart';

/// Sweeps the shared status badge across the supported text scale range.
///
/// The badge is the single highest-risk widget for large-text breakage, and for
/// a reason worth recording: it is a `Row` of an icon plus a text label that
/// usually sits NEXT TO other text — a price, a distance, a delivery time. The
/// label is short ("Open now"), so it looks harmless in isolation, but its
/// width grows with the font and it is almost never the only flexible child in
/// whatever row it lands in.
///
/// It also renders in a `Row` with a fixed-size icon, so the failure mode is a
/// horizontal overflow — the loud kind — which is why this is worth pinning
/// down rather than assuming.
void main() {
  Widget host({required bool? isOpen, required bool dense}) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        // A deliberately cramped row, mirroring how the badge is used in a card
        // footer alongside a price. If it fits here it fits in the tight case.
        body: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Rs 249', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              ShopOpenClosedBadge(isOpenNow: isOpen, dense: dense),
            ],
          ),
        ),
      ),
    );
  }

  group('the status badge survives large system text', () {
    // Both states, because the two labels are different lengths and the longer
    // one is the one that overflows.
    for (final entry in <String, bool?>{
      'open': true,
      'closed': false,
      'unknown': null,
    }.entries) {
      for (final dense in <bool>[false, true]) {
        testWidgets(
          '${entry.key}${dense ? ', dense' : ''} badge renders at every scale',
          (tester) async {
            await TextScaleSweep.acrossPhoneScales(
              tester,
              build: () => host(isOpen: entry.value, dense: dense),
              label: 'the ${entry.key} badge${dense ? ' (dense)' : ''}',
            );
          },
        );
      }
    }
  });

  group('the badge still states its meaning in words', () {
    // Scaling must not be allowed to "solve" the overflow by dropping the label
    // and leaving only a coloured dot — the whole point of the earlier contrast
    // work was that status is never conveyed by colour alone.
    for (final scale in <double>[
      TextScaling.large,
      TextScaling.xLarge,
      TextScaling.maxAccessibility,
    ]) {
      testWidgets('the label survives ${TextScaling.describe(scale)}', (
        tester,
      ) async {
        final result = await TextScaleSweep.at(
          tester,
          build: () => host(isOpen: true, dense: false),
          scale: scale,
        );

        expect(
          result.isClean,
          isTrue,
          reason: 'errors: ${result.errors.join(" | ")}',
        );
        expect(
          find.text('Open'),
          findsWidgets,
          reason: 'the open/closed wording must not disappear at scale',
        );
      });
    }
  });

  group('the badge is never squeezed out of existence', () {
    testWidgets('it keeps a usable tap target at the largest scale', (
      tester,
    ) async {
      await TextScaleSweep.at(
        tester,
        build: () => host(isOpen: true, dense: false),
        scale: TextScaling.maxSupportedScale,
      );

      TextScaleSweep.expectNotClipped(
        tester,
        find.byType(ShopOpenClosedBadge),
        label: 'the status badge',
        at: TextScaling.describe(TextScaling.maxSupportedScale),
      );
    });
  });
}
