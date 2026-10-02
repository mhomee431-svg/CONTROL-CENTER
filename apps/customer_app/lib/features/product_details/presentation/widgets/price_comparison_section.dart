import 'package:flutter/material.dart';

import '../../domain/models/product_details_models.dart';
import '../../../search/domain/models/search_models.dart';
import '../../../search/presentation/widgets/freshness_disclaimer.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/network_image_view.dart';
import '../../../../core/widgets/shop_open_closed_badge.dart';

/// Side-by-side price comparison across every shop stocking this product.
///
/// Strictly factual: it reports the observed range, the lowest price and who
/// offers it, and where each shop sits in that range. It never labels a shop
/// "best" and never implies a saving is guaranteed — prices change, so the
/// customer is comparing a snapshot.
class PriceComparisonSection extends StatelessWidget {
  final ProductDetails details;
  final void Function(ShopInventoryOffer offer) onShopTap;

  const PriceComparisonSection({
    super.key,
    required this.details,
    required this.onShopTap,
  });

  @override
  Widget build(BuildContext context) {
    final offers = details.allOffersSorted;
    // Fewer than two prices is not a comparison — render nothing rather than a
    // single-row "comparison".
    if (offers.length < 2) {
      return const SizedBox.shrink();
    }

    final low = details.lowestPrice;
    final high = details.highestPrice;
    final spread = details.priceSpread;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Price Comparison',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                '${offers.length} shops',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Prices reported by each shop for this product',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Observed range summary ─────────────────────────────────────
          if (low != null && high != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    low == high
                        ? 'All in-stock shops report ₹${low.toStringAsFixed(0)}'
                        : '₹${low.toStringAsFixed(0)} – ₹${high.toStringAsFixed(0)} across shops',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (spread != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '₹${spread.toStringAsFixed(0)} difference between the '
                      'lowest and highest in-stock shop',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  const Text(
                    'Only in-stock shops are counted here.',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.md),

          // ── Per-shop comparison rows ───────────────────────────────────
          ...offers.map(
            (offer) => _ComparisonRow(
              offer: offer,
              low: low,
              high: high,
              onTap: () => onShopTap(offer),
            ),
          ),

          const SizedBox(height: AppSpacing.sm),
          const FreshnessDisclaimer(),
        ],
      ),
    );
  }
}

class _ComparisonRow extends StatelessWidget {
  final ShopInventoryOffer offer;
  final double? low;
  final double? high;
  final VoidCallback onTap;

  const _ComparisonRow({
    required this.offer,
    required this.low,
    required this.high,
    required this.onTap,
  });

  /// Position of this price within the observed range, 0.0 (cheapest) → 1.0
  /// (dearest). Null when every shop reports the same price.
  double? get _positionInRange {
    if (low == null || high == null || high! <= low!) return null;
    return ((offer.price - low!) / (high! - low!)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final outOfStock = offer.isOutOfStock;
    final position = _positionInRange;
    final freshnessLabel = formatFreshnessText(
      offer.lastUpdated,
      backendStatus: offer.freshnessStatus,
    );
    final warn = isFreshnessWarning(freshnessLabel);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NetworkImageView(
              imageUrl: offer.shopImageUrl,
              width: 40,
              height: 40,
              borderRadius: 6,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          offer.shopName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: outOfStock
                                ? AppColors.textMuted
                                : AppColors.textLight,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      ShopOpenClosedBadge(
                        isOpenNow: offer.isOpenNow,
                        acceptingOrders: offer.isAcceptingOrders,
                        dense: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${offer.distanceInKm} km • ⭐ ${offer.rating}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                  // A relative bar makes the spread readable at a glance
                  // without asserting which shop the customer should choose.
                  if (position != null && !outOfStock) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: position,
                        minHeight: 4,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${offer.price.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: outOfStock
                        ? AppColors.textMuted
                        : AppColors.textLight,
                  ),
                ),
                if (offer.hasDiscount) ...[
                  const SizedBox(height: 1),
                  Text(
                    'MRP ₹${offer.mrp!.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textMuted,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                  Text(
                    '${offer.discountPercent}% off',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppColors.secondary,
                    ),
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  outOfStock ? 'Out of stock' : 'In stock',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: outOfStock ? AppColors.error : AppColors.secondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  freshnessLabel,
                  style: TextStyle(
                    fontSize: 10,
                    color: warn ? AppColors.error : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
