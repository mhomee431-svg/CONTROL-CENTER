import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../controllers/saved_and_history_controllers.dart';
import '../../../../core/network/api_error_handler.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/network_image_view.dart';

class SavedItemsScreen extends ConsumerWidget {
  const SavedItemsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Saved & History'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Products'),
              Tab(text: 'Shops'),
              Tab(text: 'Search'),
              Tab(text: 'Viewed'),
              Tab(text: 'Shops Viewed'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _SavedProductsTab(),
            _SavedShopsTab(),
            _RecentSearchesTab(),
            _RecentlyViewedTab(),
            _RecentlyViewedShopsTab(),
          ],
        ),
      ),
    );
  }
}

class _SavedProductsTab extends ConsumerWidget {
  const _SavedProductsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(savedProductsNotifierProvider);

    return productsAsync.when(
      data: (items) {
        if (items.isEmpty) {
          return const _EmptyStateView(
            icon: Icons.bookmark_border,
            title: 'No Saved Products',
            message: 'Items you save will appear here for easy price tracking.',
          );
        }
        return Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  ref.read(savedProductsNotifierProvider.notifier).clearAll();
                },
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text('Clear All'),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: ListTile(
                      leading: NetworkImageView(
                        imageUrl: item.imageUrl,
                        width: 50,
                        height: 50,
                        borderRadius: 8,
                      ),
                      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${item.brand} • Starts at ₹${item.lowestPrice.toInt()}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: AppColors.error),
                        onPressed: () {
                          ref.read(savedProductsNotifierProvider.notifier).toggleSave(item);
                        },
                      ),
                      onTap: () => context.push('/product/${item.productId}'),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (err, _) => Center(
            child: Text(friendlyErrorMessage(err)),
          ),
    );
  }
}

class _SavedShopsTab extends ConsumerWidget {
  const _SavedShopsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shopsAsync = ref.watch(savedShopsNotifierProvider);

    return shopsAsync.when(
      data: (shops) {
        if (shops.isEmpty) {
          return const _EmptyStateView(
            icon: Icons.storefront_outlined,
            title: 'No Saved Shops',
            message: 'Favorite nearby stores to stay updated on their inventory.',
          );
        }
        return Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  ref.read(savedShopsNotifierProvider.notifier).clearAll();
                },
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text('Clear All'),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: shops.length,
                itemBuilder: (context, index) {
                  final shop = shops[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: ListTile(
                      leading: NetworkImageView(
                        imageUrl: shop.imageUrl,
                        width: 50,
                        height: 50,
                        borderRadius: 8,
                      ),
                      title: Text(shop.name),
                      subtitle: Text('${shop.address} • ⭐ ${shop.rating}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.favorite, color: AppColors.error),
                        onPressed: () {
                          ref.read(savedShopsNotifierProvider.notifier).toggleSave(shop);
                        },
                      ),
                      onTap: () => context.push('/shop/${shop.shopId}'),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (err, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 48, color: AppColors.textMuted),
              const SizedBox(height: AppSpacing.md),
              Text(
                friendlyErrorMessage(err),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: () => ref.invalidate(savedShopsNotifierProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentSearchesTab extends ConsumerWidget {
  const _RecentSearchesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchesAsync = ref.watch(recentSearchesNotifierProvider);

    return searchesAsync.when(
      data: (searches) {
        if (searches.isEmpty) {
          return const _EmptyStateView(
            icon: Icons.search_off,
            title: 'No Recent Searches',
            message: 'Your search history will appear here.',
          );
        }
        return Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  ref.read(recentSearchesNotifierProvider.notifier).clearAll();
                },
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text('Clear All'),
              ),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: searches.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = searches[index];
                  return ListTile(
                    leading: const Icon(Icons.history, color: AppColors.textMuted),
                    title: Text(item.query),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 20, color: AppColors.textMuted),
                      onPressed: () {
                        ref.read(recentSearchesNotifierProvider.notifier).removeQuery(item.query);
                      },
                    ),
                    onTap: () => context.push('/search/results?q=${Uri.encodeComponent(item.query)}'),
                  );
                },
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (err, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 48, color: AppColors.textMuted),
              const SizedBox(height: AppSpacing.md),
              Text(
                friendlyErrorMessage(err),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: () => ref.invalidate(recentSearchesNotifierProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentlyViewedTab extends ConsumerWidget {
  const _RecentlyViewedTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewedAsync = ref.watch(recentlyViewedNotifierProvider);

    return viewedAsync.when(
      data: (items) {
        if (items.isEmpty) {
          return const _EmptyStateView(
            icon: Icons.visibility_outlined,
            title: 'No Recently Viewed',
            message: 'Products you view will appear here for quick access.',
          );
        }
        return Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  ref.read(recentlyViewedNotifierProvider.notifier).clearAll();
                },
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text('Clear All'),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: ListTile(
                      leading: NetworkImageView(
                        imageUrl: item.imageUrl,
                        width: 50,
                        height: 50,
                        borderRadius: 8,
                      ),
                      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('₹${item.price.toInt()}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 20, color: AppColors.textMuted),
                        onPressed: () {
                          ref
                              .read(recentlyViewedNotifierProvider.notifier)
                              .removeProduct(item.productId);
                        },
                      ),
                      onTap: () => context.push('/product/${item.productId}'),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (err, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 48, color: AppColors.textMuted),
              const SizedBox(height: AppSpacing.md),
              Text(
                friendlyErrorMessage(err),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: () => ref.invalidate(recentlyViewedNotifierProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentlyViewedShopsTab extends ConsumerWidget {
  const _RecentlyViewedShopsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewedAsync = ref.watch(recentlyViewedShopsNotifierProvider);

    return viewedAsync.when(
      data: (shops) {
        if (shops.isEmpty) {
          return const _EmptyStateView(
            icon: Icons.storefront_outlined,
            title: 'No Recently Viewed Shops',
            message: 'Shops you visit will appear here for quick access.',
          );
        }
        return Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  ref.read(recentlyViewedShopsNotifierProvider.notifier).clearAll();
                },
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text('Clear All'),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: shops.length,
                itemBuilder: (context, index) {
                  final shop = shops[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: ListTile(
                      leading: NetworkImageView(
                        imageUrl: shop.imageUrl,
                        width: 50,
                        height: 50,
                        borderRadius: 8,
                      ),
                      title: Text(shop.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${shop.address} • ⭐ ${shop.rating}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 20, color: AppColors.textMuted),
                        onPressed: () {
                          ref
                              .read(recentlyViewedShopsNotifierProvider.notifier)
                              .removeShop(shop.shopId);
                        },
                      ),
                      onTap: () => context.push('/shop/${shop.shopId}'),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (err, _) => Center(child: Text('Error loading recently viewed shops: $err')),
    );
  }
}

class _EmptyStateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyStateView({required this.icon, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: AppColors.textMuted),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: AppSpacing.sm),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}