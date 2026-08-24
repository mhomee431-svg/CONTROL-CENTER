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
import '../../../../core/network/api_error_handler.dart';
import '../../../../core/widgets/empty_state_view.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeDataAsync = ref.watch(homeControllerProvider);

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
                data: (data) => SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      switch (index) {
                        case 0:
                          return PromotionBanner(promotions: data.promotions);
                        case 1:
                          return CategorySection(categories: data.categories);
                        case 2:
                          return RecentSearchesSection(recentSearches: data.recentSearches);
                        case 3:
                          return ProductRowSection(
                            title: 'Popular Nearby',
                            products: data.popularProducts,
                            actionLabel: 'View All',
                            onActionTap: () => context.push('/search'),
                          );
                        case 4:
                          return ProductRowSection(
                            title: 'Recently Viewed',
                            products: data.recentlyViewed,
                          );
                        case 5:
                          return ProductRowSection(
                            title: 'Recommended For You',
                            products: data.recommendedProducts,
                          );
                        case 6:
                          return NearbyShopsSection(shops: data.nearbyShops);
                        case 7:
                          return const SizedBox(height: 40);
                        default:
                          return null;
                      }
                    },
                    childCount: 8,
                  ),
                ),
                loading: () => const SliverToBoxAdapter(child: HomeSkeletonLoader()),
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