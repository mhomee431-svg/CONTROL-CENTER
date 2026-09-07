import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/product_details_providers.dart';
import '../../domain/models/product_details_models.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/network_image_view.dart';
import '../../../../core/widgets/empty_state_view.dart';

/// "View All Nearby Shops" screen.
///
/// Shows the full list of shops that carry this product, with
/// shop-specific price, availability, distance, and freshness.
///
/// Navigation: Product → Nearby Shops → Shop → Directions
class NearbyShopsScreen extends ConsumerWidget {
  final String productId;
  const NearbyShopsScreen({super.key, required this.productId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productAsync = ref.watch(productDetailsProvider(productId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Shops'),
      ),
      body: productAsync.when(
        data: (details) => _buildBody(context, details),
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (err, stack) => EmptyStateView(
          icon: Icons.error_outline,
          title: 'Failed to load nearby shops',
          message: '$err',
          actionLabel: 'Try Again',
          onActionTap: () => ref.refresh(productDetailsProvider(productId)),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ProductDetails details) {
    final offers = details.shopOffers;

    if (offers.isEmpty) {
      return const EmptyStateView(
        icon: Icons.storefront_outlined,
        title: 'No nearby shops found',
        message: 'This product is not currently available at any nearby shop.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: offers.length,
      itemBuilder: (context, index) {
        final offer = offers[index];
        return _NearbyShopCard(offer: offer);
      },
    );
  }
}

class _NearbyShopCard extends StatelessWidget {
  final ShopInventoryOffer offer;
  const _NearbyShopCard({required this.offer});

  String _formatFreshness(DateTime lastUpdated) {
    final diff = DateTime.now().difference(lastUpdated);
    if (diff.inMinutes < 60) return 'Updated ${diff.inMinutes} mins ago';
    if (diff.inHours < 24) return 'Updated ${diff.inHours} hours ago';
    return 'Updated ${diff.inDays} days ago (Stale)';
  }

  bool _isStale(DateTime lastUpdated) {
    return DateTime.now().difference(lastUpdated).inHours > 24;
  }

  @override
  Widget build(BuildContext context) {
    final stale = _isStale(offer.lastUpdated);

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                NetworkImageView(
                  imageUrl: offer.shopImageUrl,
                  width: 56,
                  height: 56,
                  borderRadius: 8,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        offer.shopName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${offer.distanceInKm} km away • ⭐ ${offer.rating}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₹${offer.price.toInt()}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    if (offer.mrp != null && offer.mrp! > offer.price) ...[
                      Text(
                        'MRP ₹${offer.mrp!.toInt()}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ],
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: offer.isAvailable
                            ? AppColors.secondary.withValues(alpha: 0.1)
                            : AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        offer.isAvailable ? 'In Stock' : 'Out of Stock',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: offer.isAvailable ? AppColors.secondary : AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (offer.offerText != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.local_offer, size: 14, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        offer.offerText!,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 13,
                      color: stale ? AppColors.error : AppColors.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatFreshness(offer.lastUpdated),
                      style: TextStyle(
                        fontSize: 11,
                        color: stale ? AppColors.error : AppColors.textMuted,
                        fontWeight: stale ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => context.push('/shop/${offer.shopId}'),
                      icon: const Icon(Icons.storefront, size: 16),
                      label: const Text('View Shop', style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 4),
                    ElevatedButton.icon(
                      onPressed: () => context.push(
                        '/directions?shopId=${offer.shopId}&name=${Uri.encodeComponent(offer.shopName)}',
                      ),
                      icon: const Icon(Icons.directions, size: 16),
                      label: const Text('Directions', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}