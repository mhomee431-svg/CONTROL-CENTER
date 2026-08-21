import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyperlocal_customer_app/features/product_details/presentation/screens/product_details_screen.dart';

void main() {
  testWidgets('ProductDetailsScreen renders product info and price comparison offers', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        home: ProductDetailsScreen(productId: 'test_p1'),
      ),
    ));

    // Verify loading indicator appears initially
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Allow mock repository future to resolve
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Verify Product Header & Description loaded
    expect(find.text('Samsung Galaxy S24 Ultra 5G'), findsOneWidget);
    expect(find.text('₹1,29,999 - ₹1,34,999'), findsOneWidget);
    expect(find.text('Free tempered glass & back cover combo'), findsOneWidget);

    // Verify Nearby Shop Offer comparisons are rendered
    expect(find.text('Gupta Mobile & Electronics'), findsOneWidget);
    expect(find.text('Digital World Hub'), findsOneWidget);
    expect(find.text('City Electronics Outlet'), findsOneWidget);

    // Verify freshness and stock indicators exist
    expect(find.text('In Stock'), findsNWidgets(2));
    expect(find.text('Out of Stock'), findsOneWidget);

    // Verify stale inventory warning is shown for >24h updated offer
    expect(find.textContaining('(Stale)'), findsOneWidget);
  });

  testWidgets('ProductDetailsScreen shows error state on repository failure', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        home: ProductDetailsScreen(productId: 'error'),
      ),
    ));

    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.textContaining('Failed to load product details'), findsOneWidget);
  });
}