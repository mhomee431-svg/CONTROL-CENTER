import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyperlocal_app/features/product_details/data/mock_product_details_repository.dart';
import 'package:hyperlocal_app/features/product_details/domain/product_details_repository.dart';
import 'package:hyperlocal_app/features/product_details/presentation/screens/product_details_screen.dart';

void main() {
  testWidgets(
    'ProductDetailsScreen renders product info and price comparison offers',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            productDetailsRepositoryProvider.overrideWithValue(
              MockProductDetailsRepository(),
            ),
          ],
          child: const MaterialApp(
            home: ProductDetailsScreen(productId: 'test_p1'),
          ),
        ),
      );

      // Verify loading indicator appears initially
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Allow mock repository future to resolve
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Verify Product Header & Description loaded
      expect(find.text('Samsung Galaxy S24 Ultra 5G'), findsOneWidget);
      // Master MRP is repeated by every section that contextualises a price
      // (at-a-glance summary, master info, per-shop inventory cards, price
      // comparison rows, active offers), so assert presence rather than a
      // brittle exact count.
      expect(find.text('MRP ₹134999'), findsWidgets);
      // The offer text is surfaced by both the inventory card and the active
      // offers section, so presence (not uniqueness) is the right contract.
      expect(
        find.text('Free tempered glass & back cover combo'),
        findsWidgets,
      );

      // Verify Product Master sections
      expect(find.text('Variants'), findsOneWidget);
      expect(find.text('Attributes'), findsOneWidget);
      expect(find.text('Description'), findsOneWidget);
      expect(find.text('Identifiers'), findsOneWidget);

      // Verify Nearby Shop Offer comparisons are rendered.
      // Each shop surfaces in the inventory list, the price-comparison rows
      // and (where it has a deal) the active-offers section, so assert
      // presence rather than a single occurrence.
      expect(find.text('Gupta Mobile & Electronics'), findsWidgets);
      expect(find.text('Digital World Hub'), findsWidgets);
      expect(find.text('City Electronics Outlet'), findsWidgets);

      // Verify freshness and stock indicators exist
      expect(find.text('In Stock'), findsNWidgets(2));
      expect(find.text('Out of Stock'), findsOneWidget);

      // Verify stale inventory warning is shown for the >24h-old offer.
      // The shared freshness formatter renders this as the plain label
      // "Stale" (previously "(Stale)"), so assert the canonical wording.
      // It appears on both the inventory card and the comparison row.
      expect(find.text('Stale'), findsWidgets);

      // The availability disclaimer must be present: a stock reading is a
      // snapshot and must never be presented as a guarantee of arrival stock.
      // Every dynamic section repeats it so it survives partial rendering.
      expect(find.textContaining('Availability can change'), findsWidgets);

      // Verify View All Nearby Shops button
      expect(find.text('View All Nearby Shops'), findsOneWidget);
    },
  );

  testWidgets('ProductDetailsScreen shows error state on repository failure', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productDetailsRepositoryProvider.overrideWithValue(
            MockProductDetailsRepository(),
          ),
        ],
        child: const MaterialApp(
          home: ProductDetailsScreen(productId: 'error'),
        ),
      ),
    );

    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(
      find.textContaining('Failed to load product details'),
      findsOneWidget,
    );
  });

  testWidgets('ProductDetailsScreen shows empty state when no nearby shops', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productDetailsRepositoryProvider.overrideWithValue(
            MockProductDetailsRepository(),
          ),
        ],
        child: const MaterialApp(
          home: ProductDetailsScreen(productId: 'empty'),
        ),
      ),
    );

    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Product master still renders
    expect(find.text('Samsung Galaxy S24 Ultra 5G'), findsOneWidget);

    // Empty state for nearby shops
    expect(find.text('No nearby shops found'), findsOneWidget);
  });
}
