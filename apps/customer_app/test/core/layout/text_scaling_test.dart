import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hyperlocal_app/core/layout/text_scaling.dart';
import 'package:hyperlocal_app/core/theme/app_theme.dart';
import 'package:hyperlocal_app/core/widgets/shop_card.dart';
import 'package:hyperlocal_app/features/home/domain/models/home_data.dart';

/// Sweeps real widgets at the font sizes real operating systems offer.
///
/// WHY A SWEEP RATHER THAN ONE BIG VALUE
/// ------------------------------------
/// A layout that survives 2.0x but clips at 1.8x is broken in a way no single
/// large-scale test would catch, and 1.8x is a value people actually choose.
/// The scales below are the ones Android and iOS expose, so this file fails for
/// a setting somebody can actually select.
///
/// ## What "passes" means here
/// A `RenderFlex` overflow is thrown as a Flutter error, so `takeException()`
/// catching one is the assertion that nothing overflows or clips. Controls are
/// additionally checked for PRESENCE, because a control can be squeezed out of a
/// fixed-height box without throwing anything -- the failure the spec calls
/// "hidden buttons" is silent, and only an explicit finder catches it.
void main() {
  Shop shop({
    String name = 'Sharma Kirana',
    bool? isOpenNow = true,
    bool? isAcceptingOrders = true,
  }) {
    return Shop(
      id: '5',
      name: name,
      imageUrl: '',
      distance: 1.4,
      rating: 4.5,
      isVerified: true,
      isOpenNow: isOpenNow,
      isAcceptingOrders: isAcceptingOrders,
    );
  }

  /// Pumps [child] at [scale] inside a realistic phone-sized viewport.
  Future<void> pumpAt(
    WidgetTester tester,
    double scale,
    Widget child, {
    Size size = const Size(360, 640),
  }) async {
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the shop card survives every real font size', () {
    for (final scale in TextScaling.testScales) {
      testWidgets('no overflow at ${TextScaling.describe(scale)}', (
        tester,
      ) async {
        await pumpAt(tester, scale, ShopCard(shop: shop(), onTap: () {}));
        expect(
          tester.takeException(),
          isNull,
          reason: 'overflow or clipping at ${TextScaling.describe(scale)}',
        );
      });
    }

    testWidgets('a long shop name does not push the status badge away', (
      tester,
    ) async {
      // The badge sits beside the name in a Row; a long name at a large scale is
      // where "Open" gets squeezed to nothing.
      await pumpAt(
        tester,
        TextScaling.xLarge,
        ShopCard(
          shop: shop(name: 'Sharma Kirana and Provision Store'),
          onTap: () {},
        ),
      );

      expect(tester.takeException(), isNull);
      // The badge must still exist, not merely exist without overflowing.
      expect(find.text('Open'), findsOneWidget);
    });
  });
  group('the chip bar keeps its controls', () {
    // A representative fixed-height control: the filter/sort strip is exactly
    // the shape that clips silently when text grows.
    Future<void> pumpChipBar(WidgetTester tester, double scale) async {
      await pumpAt(
        tester,
        scale,
        Builder(
          builder: (context) => SizedBox(
            height: TextScaling.chipBarHeight(MediaQuery.textScalerOf(context)),
            // `Wrap`, not a `Row`: at 2.5x two side-by-side labels genuinely do
            // not fit a 360dp phone, and a real filter bar must WRAP rather than
            // overflow. Testing a Row here would assert the opposite of what the
            // app should do.
            child: Wrap(
              children: [
                Text('Filter', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(width: 8),
                Text('Sort', style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ),
      );
    }

    for (final scale in TextScaling.testScales) {
      testWidgets('nothing clipped at ${TextScaling.describe(scale)}', (
        tester,
      ) async {
        await pumpChipBar(tester, scale);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the bar GROWS with the text rather than staying at 50', (
      tester,
    ) async {
      // The regression this guards: a fixed height that happens not to throw
      // but silently cuts the label in half.
      double heightAt(double scale) =>
          TextScaling.chipBarHeight(TextScaler.linear(scale));

      expect(heightAt(TextScaling.normal), 50);
      expect(
        heightAt(TextScaling.xLarge),
        greaterThan(heightAt(TextScaling.normal)),
      );
      // At 2.0x the bar is 100dp, comfortably above the 48dp touch minimum.
      expect(heightAt(2.0), greaterThanOrEqualTo(48.0));
    });

    testWidgets('the bar is ALWAYS tall enough for the text it holds', (
      tester,
    ) async {
      // The real invariant: the scaled bar must contain the scaled label. A bar
      // that grows but still ends up shorter than its own text clips it, and
      // that is the "hidden button" failure.
      for (final scale in TextScaling.testScales) {
        await pumpChipBar(tester, scale);
        final barHeight = TextScaling.chipBarHeight(TextScaler.linear(scale));
        final labelHeight = tester.getSize(find.text('Filter')).height;
        expect(
          labelHeight,
          lessThanOrEqualTo(barHeight),
          reason:
              'the ${TextScaling.describe(scale)} label (${labelHeight.toStringAsFixed(1)}) '
              'does not fit its ${barHeight.toStringAsFixed(1)} bar',
        );
      }
    });
  });

  group('scaling policy', () {
    test('the cap is above every Android accessibility step', () {
      // If the cap were below 2.0x the app would be REDUCING a setting the user
      // deliberately chose, which is worse than any layout problem.
      expect(
        TextScaling.maxSupportedScale,
        greaterThanOrEqualTo(TextScaling.maxAccessibility),
      );
    });

    test(
      'the cap is below the iOS maximum, which is the point of having one',
      () {
        expect(
          TextScaling.maxSupportedScale,
          lessThan(3.2),
          reason: 'otherwise the clamp would never do anything',
        );
      },
    );

    test('the sweep includes a value above the cap', () {
      // Clamping must not make the layout explode; if an out-of-range scale
      // breaks the tree, the clamp is not protecting anything.
      expect(
        TextScaling.testScales.any((s) => s > TextScaling.maxSupportedScale),
        isTrue,
      );
    });

    test('the sweep includes the Android accessibility steps verbatim', () {
      for (final step in <double>[
        TextScaling.large,
        TextScaling.xLarge,
        TextScaling.maxAccessibility,
      ]) {
        expect(
          TextScaling.testScales,
          contains(step),
          reason: '${TextScaling.describe(step)} must be swept',
        );
      }
    });
  });
}
