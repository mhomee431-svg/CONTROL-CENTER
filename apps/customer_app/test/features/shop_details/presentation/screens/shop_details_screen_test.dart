import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyperlocal_customer_app/features/shop_details/data/mock_shop_details_repository.dart';
import 'package:hyperlocal_customer_app/features/shop_details/domain/shop_details_repository.dart';
import 'package:hyperlocal_customer_app/features/shop_details/presentation/screens/shop_details_screen.dart';

void main() {
  testWidgets('ShopDetailsScreen renders full shop profile with new fields',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          shopDetailsRepositoryProvider.overrideWithValue(MockShopDetailsRepository()),
        ],
        child: const MaterialApp(
          home: ShopDetailsScreen(shopId: 'test_shop_1'),
        ),
      ),
    );

    // Verify loading indicator appears initially
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Wait for mock data
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Verify ShopHeader details
    expect(find.text('Gupta Mobile & Electronics'), findsOneWidget);
    expect(find.text('OPEN'), findsOneWidget);
    expect(find.textContaining('1.2 km away'), findsOneWidget);

    // Verify verification badge
    expect(find.text('Verified'), findsOneWidget);

    // Verify categories chips
    expect(find.text('Electronics'), findsOneWidget);
    expect(find.text('Mobile Phones'), findsOneWidget);
    expect(find.text('Accessories'), findsOneWidget);

    // Verify actions exist
    expect(find.text('Call'), findsOneWidget);
    expect(find.text('Directions'), findsOneWidget);

    // Verify contact section
    expect(find.text('Contact'), findsOneWidget);
    expect(find.text('+919876543210'), findsOneWidget);

    // Verify operating hours + closed warning absent
    expect(find.text('Operating Hours'), findsOneWidget);
    expect(find.textContaining('Mon-Sun'), findsOneWidget);

    // Verify sections and trust signals
    expect(find.text('About Shop'), findsOneWidget);
    expect(find.textContaining('Inventory last updated'), findsOneWidget);

    // Verify Products Grid
    expect(find.text('Available Products'), findsOneWidget);
    expect(find.text('Smart Device Model 0'), findsOneWidget);
  });

  testWidgets('ShopDetailsScreen shows closed shop warning when not open',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          shopDetailsRepositoryProvider.overrideWithValue(MockShopDetailsRepository()),
        ],
        child: const MaterialApp(
          home: ShopDetailsScreen(shopId: 'closed'),
        ),
      ),
    );

    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Closed badge and warning shown
    expect(find.text('CLOSED'), findsOneWidget);
    expect(
      find.textContaining('This shop is currently closed'),
      findsOneWidget,
    );
    expect(find.text('Closed Corner Store'), findsOneWidget);
  });

  testWidgets('ShopDetailsScreen shows coordinates unavailable warning',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          shopDetailsRepositoryProvider.overrideWithValue(MockShopDetailsRepository()),
        ],
        child: const MaterialApp(
          home: ShopDetailsScreen(shopId: 'nocoords'),
        ),
      ),
    );

    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Coordinates unavailable warning shown
    expect(
      find.textContaining('Shop coordinates are temporarily unavailable'),
      findsOneWidget,
    );
    expect(find.text('No Coordinates Shop'), findsOneWidget);
  });

  testWidgets('ShopDetailsScreen handles error state',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          shopDetailsRepositoryProvider.overrideWithValue(MockShopDetailsRepository()),
        ],
        child: const MaterialApp(
          home: ShopDetailsScreen(shopId: 'error'), // Triggers mock exception
        ),
      ),
    );

    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.textContaining('Unable to load shop'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}