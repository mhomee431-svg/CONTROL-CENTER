import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/product_details_models.dart';
import '../../../search/domain/models/search_models.dart';
import '../../../search/presentation/widgets/freshness_disclaimer.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/network_image_view.dart';
import '../../../../core/widgets/empty_state_view.dart';

/// Displays the **SHOP INVENTORY** (dynamic availability).
///
/// This section shows shop-specific data: price, availability, distance,
/// inventory freshness, and offers. It is clearly separated from the
/// global Product Master information.
///
/// Navigation: Product → Nearby Shops → Shop → Directions
class ShopInventorySection extends StatelessWidget {
  final String productId;
  final List<ShopInventoryOffer> offers;

  const ShopInventorySection({
    super.key,
    required this.productId,
    required this.offers,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section Header ─────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Available at Nearby Shops',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                '${offers.length} found',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Shop-specific prices, availability & freshness',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Empty State ────────────────────────────────────────────────
          if (offers.isEmpty)
            const EmptyStateView(
              icon: Icons.storefront_outlined,
              title: 'No nearby shops found',
              message:
                  'This product is not currently available at any nearby shop.',
            )
          else ...[
            // ── Shop Offer Cards ─────────────────────────────────────────
            ...offers.map(
              (offer) => _ShopInventoryCard(productId: productId, offer: offer),
            ),

            // ── Availability Disclaimer ─────────────────────────────────
            // Each price/availability figure is the shop's last report, not a
            // promise about what will be on the shelf on arrival.
            const FreshnessDisclaimer(),
            const SizedBox(height: AppSpacing.sm),

            // ── View All Nearby Shops ────────────────────────────────────
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.push('/product/$productId/shops'),
                icon: const Icon(Icons.storefront_outlined),
                label: const Text('View All Nearby Shops'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ShopInventoryCard extends StatelessWidget {
  final String productId;
  final ShopInventoryOffer offer;

  const _ShopInventoryCard({required this.productId, required this.offer});

  String _formatFreshness(DateTime lastUpdated) {
    // Shared canonical formatter — identical wording to the search result card
    // and the Nearby Shops list, so the same data never reads differently.
    return formatFreshnessText(
      lastUpdated,
      backendStatus: offer.freshnessStatus,
    );
  }

  bool _isStale(DateTime lastUpdated) {
    return isFreshnessWarning(_formatFreshness(lastUpdated));
  }

  /// Availability label derived from the shop's own reported data.
  ///
  /// Stale inventory is never presented as a confident "In Stock" — the shop
  /// last reported that status more than a day ago, so the customer is told to
  /// check instead. Mirrors the wording on the Nearby Shops screen so the two
  /// price-comparison surfaces never disagree about the same data.
  String _availabilityLabel() {
    if (!offer.isAvailable) return 'Out of Stock';
    if (_isStale(offer.lastUpdated)) return 'Check stock';
    return 'In Stock';
  }

  @override
  Widget build(BuildContext context) {
    final stale = _isStale(offer.lastUpdated);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: offer.isAvailable
              ? Colors.grey.shade300
              : AppColors.error.withValues(alpha: 0.4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Shop Header Row ────────────────────────────────────────────
          Row(
            children: [
              NetworkImageView(
                imageUrl: offer.shopImageUrl,
                width: 48,
                height: 48,
                borderRadius: 8,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      offer.shopName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${offer.distanceInKm} km away • ⭐ ${offer.rating}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              // ── Price & Availability ───────────────────────────────────
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₹${offer.price.toInt()}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: !offer.isAvailable
                          ? AppColors.error.withValues(alpha: 0.1)
                          : stale
                          ? Colors.orange.withValues(alpha: 0.1)
                          : AppColors.secondary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _availabilityLabel(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: !offer.isAvailable
                            ? AppColors.error
                            : stale
                            ? Colors.orange.shade800
                            : AppColors.secondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // ── Offer Text ─────────────────────────────────────────────────
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
                  const Icon(
                    Icons.local_offer,
                    size: 14,
                    color: AppColors.primary,
                  ),
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

          // ── Freshness & Actions ────────────────────────────────────────
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Freshness indicator
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
              // Actions: View Shop → Directions
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => context.push('/shop/${offer.shopId}'),
                    icon: const Icon(Icons.storefront, size: 16),
                    label: const Text(
                      'View Shop',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 4),
                  ElevatedButton.icon(
                    onPressed: () => context.push(
                      '/directions?shopId=${offer.shopId}&name=${Uri.encodeComponent(offer.shopName)}',
                    ),
                    icon: const Icon(Icons.directions, size: 16),
                    label: const Text(
                      'Directions',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
