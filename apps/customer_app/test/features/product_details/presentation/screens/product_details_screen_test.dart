import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyperlocal_customer_app/features/product_details/data/mock_product_details_repository.dart';
import 'package:hyperlocal_customer_app/features/product_details/domain/product_details_repository.dart';
import 'package:hyperlocal_customer_app/features/product_details/presentation/screens/product_details_screen.dart';

void main() {
  testWidgets('ProductDetailsScreen renders product info and price comparison offers', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productDetailsRepositoryProvider.overrideWithValue(MockProductDetailsRepository()),
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
    expect(find.text('MRP ₹134999'), findsNWidgets(3));
    expect(find.text('Free tempered glass & back cover combo'), findsOneWidget);

    // Verify Product Master sections
    expect(find.text('Variants'), findsOneWidget);
    expect(find.text('Attributes'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Identifiers'), findsOneWidget);

    // Verify Nearby Shop Offer comparisons are rendered
    expect(find.text('Gupta Mobile & Electronics'), findsOneWidget);
    expect(find.text('Digital World Hub'), findsOneWidget);
    expect(find.text('City Electronics Outlet'), findsOneWidget);

    // Verify freshness and stock indicators exist
    expect(find.text('In Stock'), findsNWidgets(2));
    expect(find.text('Out of Stock'), findsOneWidget);

    // Verify stale inventory warning is shown for >24h updated offer
    expect(find.textContaining('(Stale)'), findsOneWidget);

    // Verify View All Nearby Shops button
    expect(find.text('View All Nearby Shops'), findsOneWidget);
  });

  testWidgets('ProductDetailsScreen shows error state on repository failure', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productDetailsRepositoryProvider.overrideWithValue(MockProductDetailsRepository()),
        ],
        child: const MaterialApp(
          home: ProductDetailsScreen(productId: 'error'),
        ),
      ),
    );

    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.textContaining('Failed to load product details'), findsOneWidget);
  });

  testWidgets('ProductDetailsScreen shows empty state when no nearby shops', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productDetailsRepositoryProvider.overrideWithValue(MockProductDetailsRepository()),
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