import 'package:hyperlocal_app/core/utils/distance_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/product_details_models.dart';
import '../../../search/domain/models/search_models.dart';
import '../../../search/presentation/widgets/freshness_disclaimer.dart';
import '../../../home/presentation/dialogs/area_pin_dialog.dart';
import '../providers/product_details_providers.dart';
import '../../../../core/location/discovery_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/network_image_view.dart';
import '../../../../core/widgets/empty_state_view.dart';
import '../../../../core/widgets/shop_open_closed_badge.dart';

/// Displays the **SHOP INVENTORY** (dynamic availability).
///
/// This section shows shop-specific data: price, availability, distance,
/// inventory freshness, and offers. It is clearly separated from the
/// global Product Master information.
///
/// Navigation: Product → Nearby Shops → Shop → Directions
///
/// Consumer on purpose: when the list is empty and the customer is NOT on a
/// cached read, the state offers the same three recoveries the "View All
/// nearby shops" screen does — widen the query, change the location, search a
/// different area. A shared section that could not offer them would leave one
/// of the two empty states silent about how to fix itself.
class ShopInventorySection extends ConsumerWidget {
  final String productId;
  final List<ShopInventoryOffer> offers;

  /// True when [offers] is empty only because the data is cached, not because
  /// the product is genuinely unavailable nearby.
  ///
  /// Kept as an explicit parameter (rather than inferred from an empty list)
  /// because an empty list is otherwise ambiguous, and the two cases need
  /// opposite copy.
  final bool unverified;

  const ShopInventorySection({
    super.key,
    required this.productId,
    required this.offers,
    this.unverified = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The VALUE is watched, not the notifier: `ref.watch(p.notifier)` returns a
    // stable object, so a radius change never notifies this widget and the
    // button's own label would keep advertising a step it can no longer take.
    final radiusKm = ref.watch(productSearchRadiusProvider);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section Header ─────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Flexible, not fixed: the title is the only variable-length part
              // of this row, and at a large text scale (or a narrow phone, or
              // the test font, where every glyph is a full em square) a rigid
              // title pushes the count off the right edge and overflows. The
              // count is what must never be lost, so the title yields.
              const Expanded(
                child: Text(
                  'Available at Nearby Shops',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
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
          // The message depends on WHY the list is empty. "No shops" and "we
          // have no current data" are different facts, and telling a customer a
          // product is unavailable when we simply have not checked is the exact
          // failure the cache-provenance work exists to prevent.
          if (offers.isEmpty)
            EmptyStateView(
              icon: unverified
                  ? Icons.cloud_off_outlined
                  : Icons.storefront_outlined,
              title: unverified
                  ? 'Availability unavailable'
                  : 'No nearby shops found',
              message: unverified
                  ? 'Showing saved product details. Reconnect to check which '
                        'nearby shops currently stock this item.'
                  : 'This product is not currently available at any nearby '
                        'shop.',
              // Two different facts, two different recoveries. An offline read
              // needs a RETRY (the live answer may differ); a live read that
              // came back empty must not be retried — re-asking the identical
              // question returns the identical empty list — so it is widened
              // instead, and the customer is told how far the next request will
              // actually reach.
              actionLabel: unverified ? 'Retry' : null,
              actionIcon: Icons.refresh,
              onActionTap: unverified
                  ? () => ref.invalidate(productDetailsProvider(productId))
                  : null,
              actions: unverified
                  ? const []
                  : [
                      if (canWidenDiscoveryRadius(radiusKm))
                        EmptyStateAction(
                          key: const Key('inventorySearchWider'),
                          icon: Icons.radar_outlined,
                          label: nextDiscoveryRadiusLabel(radiusKm),
                          onTap: () => ref
                              .read(productSearchRadiusProvider.notifier)
                              .widen(),
                        ),
                      EmptyStateAction(
                        key: const Key('inventoryChangeLocation'),
                        icon: Icons.place_outlined,
                        label: 'Change location',
                        onTap: () => context.push('/select-location'),
                      ),
                      EmptyStateAction(
                        key: const Key('inventorySearchAnotherArea'),
                        icon: Icons.pin_drop_outlined,
                        label: 'Search another area',
                        onTap: () => showAreaPinDialog(
                          context,
                          onPin: (pin) =>
                              context.push('/search-results-by-pin/$pin'),
                        ),
                      ),
                    ],
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
        // A near-invisible hand-tuned shadow (black @ 3%) replaced with the shared
        // [AppShadows.soft], so this row sits on the page the same way every
        // other card does instead of by its own private number.
        boxShadow: AppShadows.soft,
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${formatKilometers(offer.distanceInKm, style: DistanceStyle.withUnitSuffix)} • ⭐ ${offer.rating}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Open/closed comes straight from the backend's
                        // opening-hours verdict; unknown renders nothing.
                        ShopOpenClosedBadge(
                          isOpenNow: offer.isOpenNow,
                          acceptingOrders: offer.isAcceptingOrders,
                          dense: true,
                        ),
                      ],
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
                          ? AppColors.warningSurface
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
                            ? AppColors.warning
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
