import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyperlocal_customer_app/features/home/presentation/screens/home_screen.dart';
import 'package:hyperlocal_customer_app/features/home/presentation/widgets/home_search_bar.dart';
import 'package:hyperlocal_customer_app/features/home/presentation/widgets/home_skeleton_loader.dart';

void main() {
  testWidgets('HomeScreen shows loading skeleton initially, then renders data', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: HomeScreen(),
        ),
      ),
    );

    // Initial state should be loading (Shimmer)
    expect(find.byType(HomeSearchBar), findsOneWidget); // Header is always visible
    expect(find.byType(HomeSkeletonLoader), findsOneWidget);

    // Wait for mock data to load (2 seconds delay in mock repository)
    await tester.pump(const Duration(seconds: 3));

    // After loading, skeleton should be gone
    expect(find.byType(HomeSkeletonLoader), findsNothing);

    // Popular products should be visible
    expect(find.text('Samsung Galaxy S24'), findsOneWidget);

    // Scroll down to find the shops section
    await tester.scrollUntilVisible(
      find.text('Gupta Electronics'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    // Shops section should now be visible
    expect(find.text('Trusted Local Shops'), findsOneWidget);
    expect(find.text('Gupta Electronics'), findsOneWidget);
  });
}