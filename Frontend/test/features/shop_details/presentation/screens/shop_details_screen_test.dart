import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyperlocal_customer_app/features/shop_details/presentation/screens/shop_details_screen.dart';

void main() {
  testWidgets('ShopDetailsScreen renders shop info, actions, and products grid successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        home: ShopDetailsScreen(shopId: 'test_shop_1'),
      ),
    ));

    // Verify loading indicator appears initially
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Wait for mock data
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Verify ShopHeader details
    expect(find.text('Gupta Mobile & Electronics'), findsOneWidget);
    expect(find.text('OPEN'), findsOneWidget);
    expect(find.textContaining('1.2 km away'), findsOneWidget);

    // Verify actions exist
    expect(find.text('Call'), findsOneWidget);
    expect(find.text('Directions'), findsOneWidget);

    // Verify sections and trust signals
    expect(find.text('Operating Hours'), findsOneWidget);
    expect(find.textContaining('Inventory last updated'), findsOneWidget);

    // Verify Products Grid
    expect(find.text('Available Products'), findsOneWidget);
    expect(find.text('Smart Device Model 0'), findsOneWidget);
  });

  testWidgets('ShopDetailsScreen handles error state', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        home: ShopDetailsScreen(shopId: 'error'), // Triggers mock exception
      ),
    ));

    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.textContaining('Unable to load shop'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}