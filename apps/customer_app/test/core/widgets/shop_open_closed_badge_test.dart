import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/widgets/shop_open_closed_badge.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Center(child: child))),
    );
  }

  group('ShopOpenClosedBadge — reported states', () {
    testWidgets('open shop shows "Open"', (tester) async {
      await pump(
        tester,
        const ShopOpenClosedBadge(isOpenNow: true, acceptingOrders: true),
      );
      expect(find.text('Open'), findsOneWidget);
    });

    testWidgets('closed shop shows "Closed"', (tester) async {
      await pump(
        tester,
        const ShopOpenClosedBadge(isOpenNow: false, acceptingOrders: false),
      );
      expect(find.text('Closed'), findsOneWidget);
    });

    testWidgets(
      'open but not accepting orders is a distinct label',
      (tester) async {
        // The shop is trading but cannot take orders — collapsing this into
        // "Open" would hide a genuinely different situation.
        await pump(
          tester,
          const ShopOpenClosedBadge(isOpenNow: true, acceptingOrders: false),
        );
        expect(find.text('Open · No orders'), findsOneWidget);
        expect(find.text('Open'), findsNothing);
      },
    );
  });

  group('ShopOpenClosedBadge — unknown is never "Open"', () {
    testWidgets('null state renders nothing at all', (tester) async {
      await pump(tester, const ShopOpenClosedBadge(isOpenNow: null));
      expect(find.text('Open'), findsNothing);
      expect(find.text('Closed'), findsNothing);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('null state with acceptingOrders set still renders nothing',
        (tester) async {
      await pump(
        tester,
        const ShopOpenClosedBadge(isOpenNow: null, acceptingOrders: true),
      );
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('open with unreported acceptingOrders shows plain "Open"',
        (tester) async {
      // Null acceptingOrders is unknown, not "not accepting", so the badge
      // must not add the "No orders" qualifier.
      await pump(
        tester,
        const ShopOpenClosedBadge(isOpenNow: true, acceptingOrders: null),
      );
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Open · No orders'), findsNothing);
    });
  });

  group('ShopOpenClosedBadge — dense variant', () {
    testWidgets('dense still renders the same labels', (tester) async {
      await pump(
        tester,
        const ShopOpenClosedBadge(
          isOpenNow: false,
          acceptingOrders: false,
          dense: true,
        ),
      );
      expect(find.text('Closed'), findsOneWidget);
    });
  });
}
