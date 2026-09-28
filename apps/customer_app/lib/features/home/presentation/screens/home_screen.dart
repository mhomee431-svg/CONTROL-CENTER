import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../controllers/home_controller.dart';
import '../widgets/location_header.dart';
import '../widgets/home_search_bar.dart';
import '../widgets/home_skeleton_loader.dart';
import '../widgets/promotion_banner.dart';
import '../widgets/category_section.dart';
import '../widgets/recent_searches_section.dart';
import '../widgets/product_row_section.dart';
import '../widgets/nearby_shops_section.dart';
import '../widgets/saved_shops_section.dart';
import '../screens/coming_soon_screen.dart';
import '../../../location/presentation/controllers/location_controller.dart';
import '../../../../core/network/api_error_handler.dart';
import '../../../../core/widgets/empty_state_view.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeDataAsync = ref.watch(homeControllerProvider);
    // Signed-in personalisation. Resolves to an empty object for guests and new
    // customers, which keeps their home purely general discovery.
    final personalizationAsync = ref.watch(homePersonalizationProvider);
    final personalization =
        personalizationAsync.asData?.value ?? const HomePersonalization.empty();

    final savedProductCards = personalization.savedProducts
        .map(savedProductToCard)
        .toList();
    final recentProductCards = personalization.recentlyViewed
        .map(recentProductToCard)
        .toList();

    // When location resolves, refresh the home feed so nearby shops load.
    ref.listen<LocationState>(locationControllerProvider, (previous, next) {
      if (next.status == LocationStatus.success &&
          next.location != null &&
          next.location!.hasValidCoordinates) {
        // ignore: unused_result
        ref.refresh(homeControllerProvider.future);
      }
    });

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(homeControllerProvider.future),
          child: CustomScrollView(
            slivers: [
              const SliverPadding(
                padding: EdgeInsets.all(16.0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    children: [
                      LocationHeader(),
                      SizedBox(height: 16),
                      HomeSearchBar(),
                    ],
                  ),
                ),
              ),
              homeDataAsync.when(
                data: (data) {
                  // Phase 11: If the auto-detected location has no shops,
                  // show a "Coming Soon" screen instead of an empty home.
                  if (data.nearbyShops.isEmpty) {
                    return const SliverToBoxAdapter(child: ComingSoonScreen());
                  }
                  return SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      // Order follows the discovery spec. Each section
                      // renders only when the backend actually returned data
                      // for it, so an empty feed never shows a hollow header.
                      switch (index) {
                        case 0:
                          return CategorySection(categories: data.categories);
                        case 1:
                          return NearbyShopsSection(shops: data.nearbyShops);
                        case 2:
                          return RecentSearchesSection(
                            recentSearches: data.recentSearches,
                          );
                        case 3:
                          return ProductRowSection(
                            title: 'Popular Products',
                            products: data.popularProducts,
                            actionLabel: 'View All',
                            onActionTap: () => context.push('/search'),
                          );
                        case 4:
                          return PromotionBanner(promotions: data.promotions);
                        case 5:
                          // Signed-in customers get their own real history;
                          // guests fall back to any feed-provided copies.
                          return ProductRowSection(
                            title: 'Recently Viewed',
                            products: recentProductCards.isNotEmpty
                                ? recentProductCards
                                : data.recentlyViewed,
                          );
                        case 6:
                          return ProductRowSection(
                            title: 'Recommended For You',
                            products: data.recommendedProducts,
                          );
                        case 7:
                          return ProductRowSection(
                            title: 'Saved Products',
                            products: savedProductCards,
                            actionLabel: 'View All',
                            onActionTap: () => context.push('/my-favorites'),
                          );
                        case 8:
                          return SavedShopsSection(
                            shops: personalization.savedShops,
                          );
                        case 9:
                          return const SizedBox(height: 40);
                        default:
                          return null;
                      }
                    }, childCount: 10),
                  );
                },
                loading: () =>
                    const SliverToBoxAdapter(child: HomeSkeletonLoader()),
                error: (error, stack) => SliverToBoxAdapter(
                  child: _HomeErrorView(
                    error: error,
                    onRetry: () => ref.refresh(homeControllerProvider.future),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _HomeErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return EmptyStateView(
      icon: Icons.cloud_off,
      title: 'Failed to load feed',
      // User-safe copy; raw exception text never reaches the UI.
      message: friendlyErrorMessage(error),
      actionLabel: 'Try Again',
      onActionTap: onRetry,
    );
  }
}
