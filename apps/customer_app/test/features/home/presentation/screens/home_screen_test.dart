import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal_app/core/storage/local_storage_driver.dart';
import 'package:hyperlocal_app/features/search/presentation/screens/search_screen.dart';
import 'package:hyperlocal_app/features/home/domain/home_repository.dart';
import 'package:hyperlocal_app/features/home/domain/models/home_data.dart';
import 'package:hyperlocal_app/features/home/data/mock_home_repository.dart';
import 'package:hyperlocal_app/features/home/presentation/screens/home_screen.dart';
import 'package:hyperlocal_app/features/home/presentation/widgets/home_search_bar.dart';
import 'package:hyperlocal_app/features/home/presentation/widgets/home_skeleton_loader.dart';
import 'package:hyperlocal_app/features/home/presentation/widgets/promotion_banner.dart';
import 'package:hyperlocal_app/features/home/presentation/widgets/category_section.dart';
import 'package:hyperlocal_app/features/home/presentation/widgets/recent_searches_section.dart';

void main() {
  testWidgets('HomeScreen shows loading skeleton initially, then renders data', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeRepositoryProvider.overrideWithValue(MockHomeRepository()),
        ],
        child: const MaterialApp(
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
    expect(find.text('Bosch Impact Drill 13mm'), findsOneWidget);

    // Scroll down to find the shops section
    await tester.scrollUntilVisible(
      find.text('Gupta Electronics'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    // Shops section should now be visible
    expect(find.text('Nearby Shops'), findsOneWidget);
    expect(find.text('Gupta Electronics'), findsOneWidget);
  });

  testWidgets('HomeScreen shows promotion banner, categories, recent searches, and recommended sections', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeRepositoryProvider.overrideWithValue(MockHomeRepository()),
        ],
        child: const MaterialApp(
          home: HomeScreen(),
        ),
      ),
    );

    // Wait for mock data to load
    await tester.pump(const Duration(seconds: 3));

    // Promotion banner should be visible
    expect(find.byType(PromotionBanner), findsOneWidget);
    expect(find.text('Monsoon Mega Sale'), findsOneWidget);

    // Categories should be visible
    expect(find.byType(CategorySection), findsOneWidget);
    expect(find.text('Pharmacy & Healthcare'), findsOneWidget);

    // Recent searches should be visible
    expect(find.byType(RecentSearchesSection), findsOneWidget);
    expect(find.text('Paracetamol 500mg'), findsOneWidget);

    // Scroll to find recommended section
    await tester.scrollUntilVisible(
      find.text('Recommended For You'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Nivea Body Lotion'), findsOneWidget);
  });

  testWidgets('HomeScreen search bar navigates to search screen', (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const HomeScreen(),
        ),
        GoRoute(
          path: '/search',
          builder: (context, state) => const SearchScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeRepositoryProvider.overrideWithValue(MockHomeRepository()),
          // The search screen reads persisted recent-search history; use the
          // in-memory driver so the test never touches the real plugin.
          localStorageDriverProvider.overrideWithValue(InMemoryStorageDriver()),
        ],
        child: MaterialApp.router(
          routerConfig: router,
        ),
      ),
    );

    // Wait for data to load
    await tester.pump(const Duration(seconds: 3));

    // Tap the search bar.
    await tester.tap(find.byType(HomeSearchBar));
    // Use explicit pumps, NOT pumpAndSettle: the search screen's autofocused
    // TextField has an intrinsically infinite cursor-blink animation, which
    // makes "wait until no frames are scheduled" impossible.
    await tester.pump(); // start the route transition
    await tester.pump(const Duration(seconds: 1)); // finish the transition

    // Verify navigation happened (search screen has a TextField with search hint)
    expect(find.byType(SearchScreen), findsOneWidget);
  });

  testWidgets('HomeScreen shows coming-soon state when no nearby shops', (tester) async {
    // Create a repository that returns empty nearby shops
    final emptyRepo = _EmptyNearbyShopsRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeRepositoryProvider.overrideWithValue(emptyRepo),
        ],
        child: const MaterialApp(
          home: HomeScreen(),
        ),
      ),
    );

    // Wait for data to load
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    // The HomeScreen renders the ComingSoonScreen (pin-code entry) when the
    // customer's location has no registered shops yet.
    expect(find.text('Coming Soon!'), findsOneWidget);
    expect(find.text('Manually write your area pin'), findsOneWidget);
  });
}

/// Repository that returns home data with no nearby shops to test empty states.
class _EmptyNearbyShopsRepository implements HomeRepository {
  @override
  Future<HomeData> fetchHomeFeed({double? latitude, double? longitude}) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return const HomeData(
      categories: [],
      popularProducts: [],
      nearbyShops: [],
      recentSearches: [],
    );
  }
}