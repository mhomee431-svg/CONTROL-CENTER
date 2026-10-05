import 'package:flutter/material.dart';

import '../../domain/models/product_details_models.dart';
import '../../../search/presentation/widgets/freshness_disclaimer.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/network_image_view.dart';
import '../../../../core/widgets/shop_open_closed_badge.dart';

/// Active offers and discounts for this product, grouped by shop.
///
/// Every entry is backed by real data: either a genuine price below MRP
/// ([ShopInventoryOffer.hasDiscount]) or an offer label the shop published.
/// When no shop reports an offer the section renders nothing at all, rather
/// than inventing a generic "deal" banner.
class ProductOffersSection extends StatelessWidget {
  final ProductDetails details;
  final void Function(ShopInventoryOffer offer) onShopTap;

  const ProductOffersSection({
    super.key,
    required this.details,
    required this.onShopTap,
  });

  @override
  Widget build(BuildContext context) {
    final deals = details.offersWithDeals;
    if (deals.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Offers',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                '${deals.length} available',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Discounts and offers currently reported by shops',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: AppSpacing.md),

          ...deals.map(
            (offer) => _OfferTile(offer: offer, onTap: () => onShopTap(offer)),
          ),

          const SizedBox(height: AppSpacing.sm),
          const FreshnessDisclaimer(),
        ],
      ),
    );
  }
}

class _OfferTile extends StatelessWidget {
  final ShopInventoryOffer offer;
  final VoidCallback onTap;

  const _OfferTile({required this.offer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label = offer.offerText;
    final hasLabel = label != null && label.isNotEmpty;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
        ),
        child: Row(
          children: [
            NetworkImageView(
              imageUrl: offer.shopImageUrl,
              width: 44,
              height: 44,
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
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
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
                  // Only shown when the shop actually published offer copy.
                  if (hasLabel) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(
                          Icons.local_offer,
                          size: 12,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 3),
                  Text(
                    '${offer.distanceInKm} km • ${offer.isOutOfStock ? 'Out of stock' : 'In stock'}',
                    style: TextStyle(
                      fontSize: 11,
                      color: offer.isOutOfStock
                          ? AppColors.error
                          : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${offer.price.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                // The saving is only stated when MRP makes it real.
                if (offer.hasDiscount) ...[
                  Text(
                    'MRP ₹${offer.mrp!.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textMuted,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${offer.discountPercent}% off',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.secondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
