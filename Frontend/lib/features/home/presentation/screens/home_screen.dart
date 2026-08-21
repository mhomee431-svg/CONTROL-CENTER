import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../controllers/home_controller.dart';
import '../widgets/location_header.dart';
import '../widgets/home_search_bar.dart';
import '../widgets/home_skeleton_loader.dart';
import '../../../../core/widgets/product_card.dart';
import '../../../../core/widgets/shop_card.dart';
import '../../../../core/widgets/category_card.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/home_data.dart';

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
                          return _buildCategories(context, data.categories);
                        case 1:
                          return _buildSectionHeader(context, 'Recent Searches');
                        case 2:
                          return _buildRecentSearches(context, data.recentSearches);
                        case 3:
                          return _buildSectionHeader(context, 'Popular Nearby');
                        case 4:
                          return _buildPopularProducts(context, data.popularProducts);
                        case 5:
                          return _buildSectionHeader(context, 'Trusted Local Shops');
                        case 6:
                          return _buildNearbyShops(context, data.nearbyShops);
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
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.cloud_off, size: 64, color: AppColors.textMuted),
                          const SizedBox(height: 16),
                          Text(
                            'Failed to load feed',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '$error',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.textMuted),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: () => ref.refresh(homeControllerProvider.future),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Try Again'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategories(BuildContext context, List<Category> categories) {
    return SizedBox(
      height: 90,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index];
          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: CategoryCard(
              category: category,
              onTap: () => context.push('/search'),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return SectionHeader(title: title);
  }

  Widget _buildRecentSearches(BuildContext context, List<String> recentSearches) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: recentSearches
            .map(
              (search) => GestureDetector(
                onTap: () => context.push('/search'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.history, size: 16, color: AppColors.textMuted),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        search,
                        style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildPopularProducts(BuildContext context, List<Product> products) {
    return SizedBox(
      height: 240,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        itemCount: products.length,
        itemBuilder: (context, index) {
          final product = products[index];
          return ProductCard(
            product: product,
            onTap: () => context.push('/search'),
          );
        },
      ),
    );
  }

  Widget _buildNearbyShops(BuildContext context, List<Shop> shops) {
    return SizedBox(
      height: 180,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        itemCount: shops.length,
        itemBuilder: (context, index) {
          final shop = shops[index];
          return ShopCard(
            shop: shop,
            onTap: () => context.push('/search'),
          );
        },
      ),
    );
  }
}