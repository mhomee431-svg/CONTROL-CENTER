import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/network_image_view.dart';
import '../../domain/models/search_models.dart';

/// Result card for a shop's product offering.
///
/// Communicates the core search answer:
/// "Which nearby shop has this product, at what price, and how far away?"
///
/// Also surfaces inventory freshness clearly so stale data is never
/// presented as guaranteed real-time stock.
class ShopProductCard extends StatelessWidget {
  final ShopProductResult result;
  final VoidCallback? onTap;
  final VoidCallback? onShopTap;
  final VoidCallback? onShare;

  const ShopProductCard({
    super.key,
    required this.result,
    this.onTap,
    this.onShopTap,
    this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final outOfStock = result.isOutOfStock;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: outOfStock
              ? AppColors.error.withValues(alpha: 0.25)
              : Colors.grey.shade200,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product Image
              SizedBox(
                width: 80,
                height: 80,
                child: Stack(
                  children: [
                    NetworkImageView(
                      imageUrl: result.productImageUrl,
                      borderRadius: 8,
                    ),
                    // Share action (top-right of the image)
                    if (onShare != null)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Material(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: onShare,
                            child: const Padding(
                              padding: EdgeInsets.all(5),
                              child: Icon(
                                Icons.share,
                                size: 13,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (result.hasDiscount)
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${result.discountPercent}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    // Offer indicator badge
                    if (result.offerText != null)
                      Positioned(
                        bottom: 6,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.secondary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Icon(
                            Icons.local_offer,
                            size: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // Product & Shop Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name + variant
                    Text(
                      result.productName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    if (result.variant != null && result.variant!.isNotEmpty)
                      Text(
                        result.variant!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    const SizedBox(height: 4),
                    // Shop name (tappable)
                    InkWell(
                      onTap: onShopTap,
                      child: Row(
                        children: [
                          const Icon(Icons.storefront, size: 14, color: AppColors.textMuted),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              result.shopName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Price + MRP
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '₹${result.price.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: AppColors.textLight,
                          ),
                        ),
                        if (result.hasDiscount) ...[
                          const SizedBox(width: 6),
                          Text(
                            '₹${result.mrp!.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ],
                        if (result.hasDiscount) ...[
                          const SizedBox(width: 6),
                          Text(
                            '${result.discountPercent}% OFF',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.secondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Trust signals row: distance, rating, availability
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 14, color: AppColors.textMuted),
                        const SizedBox(width: 2),
                        Text(
                          '${result.distanceInKm.toStringAsFixed(1)} km',
                          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        const Icon(Icons.star, size: 14, color: Colors.amber),
                        const SizedBox(width: 2),
                        Text(
                          result.shopRating.toStringAsFixed(1),
                          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        _AvailabilityBadge(result: result),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Freshness signal
                    _FreshnessRow(result: result),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvailabilityBadge extends StatelessWidget {
  final ShopProductResult result;
  const _AvailabilityBadge({required this.result});

  @override
  Widget build(BuildContext context) {
    // Never present stale/unknown inventory as guaranteed real-time stock.
    final stale = result.freshness == FreshnessLevel.stale ||
        result.freshness == FreshnessLevel.unknown;
    final outOfStock = result.isOutOfStock;

    if (outOfStock) {
      return const Row(
        children: [
          Icon(Icons.cancel, size: 14, color: AppColors.error),
          SizedBox(width: 2),
          Text(
            'Out of Stock',
            style: TextStyle(fontSize: 11, color: AppColors.error),
          ),
        ],
      );
    }

    // Low stock
    if (result.availability == InventoryAvailability.lowStock) {
      return const Row(
        children: [
          Icon(Icons.inventory_2, size: 14, color: Colors.orange),
          SizedBox(width: 2),
          Text(
            'Low Stock',
            style: TextStyle(fontSize: 11, color: Colors.orange),
          ),
        ],
      );
    }

    if (stale) {
      return const Row(
        children: [
          Icon(Icons.help_outline, size: 14, color: AppColors.textMuted),
          SizedBox(width: 2),
          Text(
            'Check availability',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      );
    }

    return const Row(
      children: [
        Icon(Icons.check_circle, size: 14, color: AppColors.secondary),
        SizedBox(width: 2),
        Text(
          'In Stock',
          style: TextStyle(fontSize: 11, color: AppColors.secondary),
        ),
      ],
    );
  }
}

class _FreshnessRow extends StatelessWidget {
  final ShopProductResult result;
  const _FreshnessRow({required this.result});

  @override
  Widget build(BuildContext context) {
    final stale = result.freshness == FreshnessLevel.stale;
    final text = _formatFreshness(result.lastUpdated);

    return Row(
      children: [
        Icon(
          Icons.access_time,
          size: 13,
          color: stale ? AppColors.error : AppColors.textMuted,
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 10,
            color: stale ? AppColors.error : AppColors.textMuted,
            fontWeight: stale ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        if (stale) ...[
          const SizedBox(width: 4),
          const Text(
            '— stock info may be outdated',
            style: TextStyle(fontSize: 10, color: AppColors.error),
          ),
        ],
      ],
    );
  }

  String _formatFreshness(DateTime dateTime) {
    final difference = DateTime.now().difference(dateTime);
    switch (result.freshness) {
      case FreshnessLevel.fresh:
        return 'Fresh · updated just now';
      case FreshnessLevel.recent:
        if (difference.inMinutes < 60) return 'Updated ${difference.inMinutes}m ago';
        if (difference.inHours < 24) return 'Updated ${difference.inHours}h ago';
        return 'Updated ${difference.inDays}d ago';
      case FreshnessLevel.stale:
        if (difference.inHours < 24) return 'Updated ${difference.inHours}h ago';
        return 'Updated ${difference.inDays}d ago';
      case FreshnessLevel.unknown:
        return 'Freshness unknown';
    }
  }
}