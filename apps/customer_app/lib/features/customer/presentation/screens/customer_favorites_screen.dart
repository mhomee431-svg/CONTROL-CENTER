import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/empty_state_view.dart';
import '../../../../core/widgets/network_image_view.dart';
import '../controllers/customer_controller.dart';
import '../../domain/models/customer_models.dart';

/// Customer favourites screen — live data from the backend,
/// filterable by item type with one-tap remove.
class CustomerFavoritesScreen extends ConsumerStatefulWidget {
  const CustomerFavoritesScreen({super.key});

  @override
  ConsumerState<CustomerFavoritesScreen> createState() =>
      _CustomerFavoritesScreenState();
}

class _CustomerFavoritesScreenState
    extends ConsumerState<CustomerFavoritesScreen> {
  String? _selectedType;

  Future<void> _refresh() async {
    ref.invalidate(customerFavoritesProvider);
    return ref.read(customerFavoritesProvider(_selectedType).future);
  }

  @override
  Widget build(BuildContext context) {
    final favoritesAsync = ref.watch(customerFavoritesProvider(_selectedType));

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Favourites'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildTypeFilter(),
          const Divider(height: 1),
          Expanded(
            child: favoritesAsync.when(
              data: (items) {
                if (items.isEmpty) {
                  return const EmptyStateView(
                    icon: Icons.favorite_border,
                    title: 'No favourites yet',
                    message:
                        'Tap the heart on any product or shop to save it here.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final fav = items[index];
                      return _FavoriteCard(
                        favorite: fav,
                        onRemove: () => _remove(fav),
                      );
                    },
                  ),
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator.adaptive()),
              error: (err, st) => const Center(
                child: EmptyStateView(
                  icon: Icons.error_outline,
                  title: 'Couldn\'t load favourites',
                  message: 'Something went wrong. Please try again.',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeFilter() {
    final types = ['PRODUCT', 'SHOP', 'BRAND', 'CATEGORY', 'SHOP_PRODUCT'];
    final labels = {
      'PRODUCT': 'Products',
      'SHOP': 'Shops',
      'BRAND': 'Brands',
      'CATEGORY': 'Categories',
      'SHOP_PRODUCT': 'Listings',
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 8,
      ),
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('All'),
            selected: _selectedType == null,
            onSelected: (_) => setState(() => _selectedType = null),
          ),
          for (final t in types) ...[
            const SizedBox(width: 6),
            ChoiceChip(
              label: Text(labels[t] ?? t),
              selected: _selectedType == t,
              onSelected: (_) => setState(() => _selectedType = t),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _remove(CustomerFavorite fav) async {
    final nowFavorited = await ref
        .read(customerFavoriteToggleControllerProvider.notifier)
        .toggle(fav.itemType, fav.itemId);
    if (!mounted) return;
    if (!nowFavorited) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Removed from favourites')));
    } else {
      ref.invalidate(customerFavoritesProvider);
    }
  }
}

class _FavoriteCard extends StatelessWidget {
  final CustomerFavorite favorite;
  final VoidCallback onRemove;

  const _FavoriteCard({required this.favorite, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final item = favorite.item;
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        leading: SizedBox(
          width: 52,
          height: 52,
          child: item?.imageUrl != null
              ? NetworkImageView(imageUrl: item!.imageUrl!, borderRadius: 8)
              : Container(
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.favorite, color: AppColors.primary),
                ),
        ),
        title: Text(
          item?.name ?? 'Item #${favorite.itemId}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          _typeLabel(favorite.itemType),
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: AppColors.error),
          tooltip: 'Remove',
          onPressed: onRemove,
        ),
        onTap: item != null && favorite.itemType == 'PRODUCT'
            ? () => context.push('/product/${item.id}')
            : null,
      ),
    );
  }

  String _typeLabel(String type) => switch (type) {
    'PRODUCT' => 'Product',
    'SHOP' => 'Shop',
    'BRAND' => 'Brand',
    'CATEGORY' => 'Category',
    'SHOP_PRODUCT' => 'Shop listing',
    _ => type,
  };
}
