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
import 'package:hyperlocal_app/features/home/presentation/widgets/saved_shops_section.dart';
import 'package:hyperlocal_app/features/saved_and_history/domain/models/storage_models.dart';

/// Serves a completely empty feed so the test can prove that no discovery
/// section is rendered without backing data.
class _EmptyHomeRepository implements HomeRepository {
  @override
  Future<HomeData> fetchHomeFeed({double? latitude, double? longitude}) async =>
      const HomeData(
        categories: [],
        popularProducts: [],
        nearbyShops: [],
        recentSearches: [],
      );

  @override
  Future<List<Shop>> fetchShopsByPincode(String pincode) async => const [];
}

void main() {
  testWidgets(
    'HomeScreen shows loading skeleton initially, then renders data',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            homeRepositoryProvider.overrideWithValue(MockHomeRepository()),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );

      // Initial state should be loading (Shimmer)
      expect(
        find.byType(HomeSearchBar),
        findsOneWidget,
      ); // Header is always visible
      expect(find.byType(HomeSkeletonLoader), findsOneWidget);

      // Wait for mock data to load (2 seconds delay in mock repository)
      await tester.pump(const Duration(seconds: 3));

      // After loading, skeleton should be gone
      expect(find.byType(HomeSkeletonLoader), findsNothing);

      // Popular products sit below categories/shops, so scroll to reach them.
      await tester.scrollUntilVisible(
        find.text('Bosch Impact Drill 13mm'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Bosch Impact Drill 13mm'), findsOneWidget);
      expect(find.text('Popular Products'), findsOneWidget);

      // Scroll down to find the shops section
      await tester.scrollUntilVisible(
        find.text('Gupta Electronics'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );

      // Shops section should now be visible
      expect(find.text('Nearby Shops'), findsOneWidget);
      expect(find.text('Gupta Electronics'), findsOneWidget);
    },
  );

  testWidgets(
    'HomeScreen shows promotion banner, categories, recent searches, and recommended sections',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            homeRepositoryProvider.overrideWithValue(MockHomeRepository()),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );

      // Wait for mock data to load
      await tester.pump(const Duration(seconds: 3));

      // Categories render near the top of the feed.
      expect(find.byType(CategorySection), findsOneWidget);
      expect(find.text('Popular Categories'), findsOneWidget);
      expect(find.text('Pharmacy & Healthcare'), findsOneWidget);

      // Recent searches sit below categories and nearby shops.
      await tester.scrollUntilVisible(
        find.text('Paracetamol 500mg'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byType(RecentSearchesSection), findsOneWidget);
      expect(find.text('Recent Searches'), findsOneWidget);

      // Offers render after the popular products row.
      await tester.scrollUntilVisible(
        find.text('Monsoon Mega Sale'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byType(PromotionBanner), findsOneWidget);
      expect(find.text('Latest Offers'), findsOneWidget);

      // Scroll to find recommended section
      await tester.scrollUntilVisible(
        find.text('Recommended For You'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Nivea Body Lotion'), findsOneWidget);
    },
  );

  testWidgets('no section renders when the backend returned no data', (
    tester,
  ) async {
    // A feed that is completely empty must not produce a single section
    // header — the screen shows only the header + search bar.
    final emptyRepo = _EmptyHomeRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [homeRepositoryProvider.overrideWithValue(emptyRepo)],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Header and search are always present.
    expect(find.byType(HomeSearchBar), findsOneWidget);
    expect(find.byKey(const Key('homeProfileButton')), findsOneWidget);

    // No discovery section may be shown when there is no data behind it.
    expect(find.text('Popular Categories'), findsNothing);
    expect(find.text('Nearby Shops'), findsNothing);
    expect(find.text('Recent Searches'), findsNothing);
    expect(find.text('Popular Products'), findsNothing);
    expect(find.text('Latest Offers'), findsNothing);
    expect(find.text('Recently Viewed'), findsNothing);
    expect(find.text('Recommended For You'), findsNothing);
    expect(find.byType(PromotionBanner), findsNothing);
    expect(find.byType(CategorySection), findsNothing);
    expect(find.byType(RecentSearchesSection), findsNothing);
  });

  testWidgets('header exposes both the location and the profile entry', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
        GoRoute(
          path: '/profile',
          builder: (context, state) =>
              const Scaffold(body: Text('ProfilePage')),
        ),
        GoRoute(
          path: '/select-location',
          builder: (context, state) =>
              const Scaffold(body: Text('SelectLocationPage')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeRepositoryProvider.overrideWithValue(MockHomeRepository()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump(const Duration(seconds: 3));

    expect(find.byKey(const Key('homeProfileButton')), findsOneWidget);

    await tester.tap(find.byKey(const Key('homeProfileButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('ProfilePage'), findsOneWidget);
  });

  testWidgets('no personal section renders for a guest / new customer', (
    tester,
  ) async {
    // Default auth state is not authenticated, so personalisation resolves to
    // empty even though the feed itself is populated.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeRepositoryProvider.overrideWithValue(MockHomeRepository()),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump(const Duration(seconds: 3));

    // General discovery is present...
    expect(find.text('Popular Categories'), findsOneWidget);

    // ...but no personal sections are invented.
    expect(find.text('Saved Products'), findsNothing);
    expect(find.text('Saved Shops'), findsNothing);
    expect(find.byType(SavedShopsSection), findsNothing);
  });

  testWidgets(
    'SavedShopsSection renders real saved shops and hides when empty',
    (tester) async {
      final shop = SavedShopItem(
        shopId: '9',
        name: 'Anand Medical',
        address: 'MG Road, Indore',
        imageUrl: '',
        rating: 4.6,
        savedAt: DateTime(2026, 1, 1),
      );

      // Empty list collapses to nothing.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(child: SavedShopsSection(shops: <SavedShopItem>[])),
          ),
        ),
      );
      expect(find.text('Saved Shops'), findsNothing);

      // Populated list shows the header and the real shop details.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SavedShopsSection(shops: [shop])),
        ),
      );
      expect(find.text('Saved Shops'), findsOneWidget);
      expect(find.text('Anand Medical'), findsOneWidget);
      expect(find.text('MG Road, Indore'), findsOneWidget);
      expect(find.text('4.6'), findsOneWidget);
    },
  );

  testWidgets('HomeScreen search bar navigates to search screen', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
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
        child: MaterialApp.router(routerConfig: router),
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

  testWidgets('HomeScreen shows coming-soon state when no nearby shops', (
    tester,
  ) async {
    // Create a repository that returns empty nearby shops
    final emptyRepo = _EmptyNearbyShopsRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [homeRepositoryProvider.overrideWithValue(emptyRepo)],
        child: const MaterialApp(home: HomeScreen()),
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

  @override
  Future<List<Shop>> fetchShopsByPincode(String pincode) async => const [];
}
