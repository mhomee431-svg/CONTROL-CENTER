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
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
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
                            horizontal: 4,
                            vertical: 1,
                          ),
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
                            horizontal: 4,
                            vertical: 1,
                          ),
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
                          const Icon(
                            Icons.storefront,
                            size: 14,
                            color: AppColors.textMuted,
                          ),
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
                          if (result.isOpenNow != null) ...[
                            const SizedBox(width: 6),
                            _OpenClosedBadge(result: result),
                          ],
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
                    // Trust signals row: distance, rating, availability.
                    //
                    // Distance and rating are CONDITIONAL on being real values
                    // (`hasKnownDistance` / `isRated`), not printed unconditionally:
                    // the backend sends 0.0 for an unresolvable distance and for a
                    // shop nobody has reviewed yet, and a confident "0.0 km" or a
                    // star beside "0.0" states a fact the data does not contain. The
                    // rules live on the model so this card and the shop card cannot
                    // drift apart.
                    Row(
                      children: [
                        if (result.hasKnownDistance) ...[
                          const Icon(
                            Icons.location_on_outlined,
                            size: 14,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${result.distanceInKm.toStringAsFixed(1)} km',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                        ],
                        if (result.isRated) ...[
                          const Icon(Icons.star, size: 14, color: Colors.amber),
                          const SizedBox(width: 2),
                          Text(
                            result.shopRating.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                        ],
                        _AvailabilityBadge(result: result),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Freshness signal
                    _FreshnessRow(result: result),
                    const SizedBox(height: AppSpacing.sm),
                    // Offer copy is shown only when the backend supplied one.
                    if (result.offerText != null &&
                        result.offerText!.isNotEmpty) ...[
                      Text(
                        result.offerText!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.secondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    // Shop is the primary CTA: a result is "this product, at
                    // this nearby shop". Product is the secondary action.
                    _CardActions(onShopTap: onShopTap, onProductTap: onTap),
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

/// Primary/secondary actions for a result card.
///
/// Each button renders only when its handler is supplied, so a card never
/// offers an action that does nothing.
class _CardActions extends StatelessWidget {
  final VoidCallback? onShopTap;
  final VoidCallback? onProductTap;

  const _CardActions({this.onShopTap, this.onProductTap});

  @override
  Widget build(BuildContext context) {
    if (onShopTap == null && onProductTap == null) {
      return const SizedBox.shrink();
    }
    return Row(
      children: [
        if (onShopTap != null)
          Expanded(
            flex: 2,
            child: FilledButton(
              key: const Key('viewShopButton'),
              onPressed: onShopTap,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 34),
                padding: EdgeInsets.zero,
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('View Shop'),
            ),
          ),
        if (onShopTap != null && onProductTap != null)
          const SizedBox(width: AppSpacing.sm),
        if (onProductTap != null)
          Expanded(
            flex: 1,
            child: OutlinedButton(
              key: const Key('viewProductButton'),
              onPressed: onProductTap,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 34),
                padding: EdgeInsets.zero,
                textStyle: const TextStyle(fontSize: 12),
              ),
              child: const Text('View Product'),
            ),
          ),
      ],
    );
  }
}

class _OpenClosedBadge extends StatelessWidget {
  final ShopProductResult result;
  const _OpenClosedBadge({required this.result});

  @override
  Widget build(BuildContext context) {
    // Only ever rendered when isOpenNow != null (guarded by the caller), so a
    // missing reading can never be presented as "Open".
    final open = result.isOpenNow == true;
    // Open-but-not-accepting is a distinct, honest state: the shop is trading
    // but can't take orders right now.
    final label = open
        ? (result.isAcceptingOrders == false ? 'Open · No orders' : 'Open')
        : 'Closed';
    final color = open ? AppColors.secondary : AppColors.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
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
    final stale =
        result.freshness == FreshnessLevel.stale ||
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
    // Rendered from the shared canonical formatter so this card, the product
    // details sheet and the nearby-shops list can never disagree.
    final label = formatFreshnessText(
      result.lastUpdated,
      backendStatus: result.freshnessStatusRaw,
    );
    final warn = isFreshnessWarning(label);

    return Row(
      children: [
        Icon(
          Icons.access_time,
          size: 13,
          color: warn ? AppColors.error : AppColors.textMuted,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: warn ? AppColors.error : AppColors.textMuted,
            fontWeight: warn ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        if (warn) ...[
          const SizedBox(width: 4),
          const Expanded(
            child: Text(
              '— stock info may be outdated',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: AppColors.error),
            ),
          ),
        ],
      ],
    );
  }
}
