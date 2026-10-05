import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/widgets/shop_card.dart';
import 'package:hyperlocal_app/features/home/domain/models/home_data.dart';

/// The Shop Card (Master Spec: Shop Discovery / Shop Card).
///
/// The card is the one place a customer decides whether a shop is worth tapping,
/// so what matters is that it shows each fact it HAS, and shows nothing where the
/// backend reported nothing. The second half is the harder half: an "Open" badge
/// invented from silence is a lie the customer only discovers on arrival.
void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    required Shop shop,
    String? contextLabel,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              height: 220,
              child: ShopCard(
                shop: shop,
                contextLabel: contextLabel,
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  Shop shop({
    String name = 'Sharma Kirana',
    double distance = 1.4,
    double rating = 4.5,
    bool isVerified = true,
    bool? isOpenNow,
    bool? isAcceptingOrders,
    String? contextLabel,
  }) {
    return Shop(
      id: '5',
      name: name,
      imageUrl: '',
      distance: distance,
      rating: rating,
      isVerified: isVerified,
      isOpenNow: isOpenNow,
      isAcceptingOrders: isAcceptingOrders,
      contextLabel: contextLabel,
    );
  }

  group('what the card shows', () {
    testWidgets('image, name, rating and distance', (tester) async {
      await pumpCard(tester, shop: shop());

      expect(find.text('Sharma Kirana'), findsOneWidget);
      expect(find.text('4.5'), findsOneWidget);
      expect(find.text('1.4 km'), findsOneWidget);
      // Verification is a badge on the image, and it IS shown when verified.
      expect(find.text('Verified'), findsOneWidget);
    });

    testWidgets('the open badge when the backend reported open', (
      tester,
    ) async {
      await pumpCard(tester, shop: shop(isOpenNow: true));
      expect(find.text('Open'), findsOneWidget);
    });

    testWidgets('closed when the backend reported closed', (tester) async {
      await pumpCard(tester, shop: shop(isOpenNow: false));
      expect(find.text('Closed'), findsOneWidget);
    });

    testWidgets('open-but-not-taking-orders is its own state', (tester) async {
      // The customer can visit but cannot order ahead — collapsing this into
      // "Open" would promise an order the shop will refuse.
      await pumpCard(
        tester,
        shop: shop(isOpenNow: true, isAcceptingOrders: false),
      );
      expect(find.text('Open · No orders'), findsOneWidget);
    });

    testWidgets('an unverified shop gets no verification badge', (
      tester,
    ) async {
      await pumpCard(tester, shop: shop(isVerified: false));
      expect(find.text('Verified'), findsNothing);
    });
  });

  group('what the card must NOT show', () {
    testWidgets('no badge at all when the open state is unreported', (
      tester,
    ) async {
      await pumpCard(tester, shop: shop());

      // The important negative: silence is not evidence of being open.
      expect(find.text('Open'), findsNothing);
      expect(find.text('Closed'), findsNothing);
      expect(find.text('Open · No orders'), findsNothing);
    });

    testWidgets('no distance chip when the distance is unknown', (
      tester,
    ) async {
      // 0 is this API's "not known" sentinel; "0.0 km" would read as "you are
      // standing in it".
      await pumpCard(tester, shop: shop(distance: 0));
      expect(find.textContaining('km'), findsNothing);
    });

    testWidgets('"New" instead of a confident 0.0 rating', (tester) async {
      await pumpCard(tester, shop: shop(rating: 0));
      expect(find.text('New'), findsOneWidget);
      expect(find.text('0.0'), findsNothing);
    });

    testWidgets('no context line unless a caller supplies one', (tester) async {
      await pumpCard(tester, shop: shop(isVerified: false));

      // Nothing invented: the card does not synthesize a price or a stock count
      // from the absence of context.
      expect(find.textContaining('₹'), findsNothing);
      expect(find.textContaining('left'), findsNothing);
    });
  });

  group('the optional context line', () {
    testWidgets('renders the caller-supplied label', (tester) async {
      await pumpCard(tester, shop: shop(), contextLabel: 'from ₹120');
      expect(find.text('from ₹120'), findsOneWidget);
    });

    testWidgets('falls back to the model label', (tester) async {
      await pumpCard(tester, shop: shop(contextLabel: 'Sector 18'));
      expect(find.text('Sector 18'), findsOneWidget);
    });

    testWidgets('a blank label renders no line', (tester) async {
      // A caller passing '' must not reserve a line of the card for nothing.
      await pumpCard(tester, shop: shop(), contextLabel: '   ');
      expect(find.text(''), findsNothing);
    });
  });

  group('the View Shop CTA', () {
    // Counts taps on the card. Returns the live counter, NOT a snapshot: an int
    // returned by value here would be captured before the tap and always read 0.
    Future<List<int>> pumpCounting(WidgetTester tester) async {
      final taps = <int>[0];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                height: 220,
                child: ShopCard(shop: shop(), onTap: () => taps[0]++),
              ),
            ),
          ),
        ),
      );
      return taps;
    }

    // Disposed in a finally rather than via addTearDown: flutter_test checks
    // that no handle is still active before it runs teardown callbacks.
    testWidgets('the whole card is the CTA', (tester) async {
      final taps = await pumpCounting(tester);
      await tester.tap(find.text('Sharma Kirana'));
      await tester.pump();
      expect(taps[0], 1);
    });

    testWidgets('it is announced as a button', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await pumpCounting(tester);
        expect(
          tester.getSemantics(find.byType(ShopCard)).label,
          contains('View shop'),
        );
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('it is VISIBLE, not only announced', (tester) async {
      // A card with no visible affordance reads as static content. The chevron is
      // the cue — chosen over a second button so the card is not overloaded.
      await pumpCard(tester, shop: shop());
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('the chevron is the SAME action, not a second one', (
      tester,
    ) async {
      final taps = await pumpCounting(tester);
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pump();
      // Part of the card, so it fires the same navigation rather than a second,
      // different action.
      expect(taps[0], 1);
    });

    testWidgets('a screen reader still hears the card facts', (tester) async {
      // Regression guard: merging the CTA's semantics must not EXCLUDE the
      // children's text, or the name / rating / distance / open state — the
      // reason the card exists — would be silent for a screen-reader user.
      final semantics = tester.ensureSemantics();
      try {
        await pumpCard(tester, shop: shop(isOpenNow: true, distance: 1.4));
        final label = tester.getSemantics(find.byType(ShopCard)).label;
        expect(label, contains('View shop'));
        expect(label, contains('Sharma Kirana'));
      } finally {
        semantics.dispose();
      }
    });
  });
}
