import 'package:flutter/material.dart';
import '../../../../core/widgets/skeletons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../home/presentation/dialogs/area_pin_dialog.dart';
import '../providers/product_details_providers.dart';
import '../../domain/models/product_details_models.dart';
import '../../../search/domain/models/search_models.dart';
import '../../../search/presentation/widgets/freshness_disclaimer.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/network_image_view.dart';
import '../../../../core/location/discovery_radius.dart';
import '../../../../core/widgets/empty_state_view.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_loading_view.dart';
import '../../../../core/widgets/shop_open_closed_badge.dart';

/// "View All Nearby Shops" screen.
///
/// Shows the full list of shops that carry this product, with
/// shop-specific price, availability, distance, and freshness.
///
/// Navigation: Product → Nearby Shops → Shop → Directions
class NearbyShopsScreen extends ConsumerStatefulWidget {
  final String productId;
  const NearbyShopsScreen({super.key, required this.productId});

  @override
  ConsumerState<NearbyShopsScreen> createState() => _NearbyShopsScreenState();
}

class _NearbyShopsScreenState extends ConsumerState<NearbyShopsScreen> {
  _ShopSort _sort = _ShopSort.nearest;
  bool _inStockOnly = false;

  @override
  Widget build(BuildContext context) {
    final productAsync = ref.watch(productDetailsProvider(widget.productId));

    return Scaffold(
      appBar: AppBar(title: const Text('Nearby Shops')),
      body: productAsync.when(
        data: (details) => _buildBody(context, details),
        // A LIST of shops, so the placeholder is a list of rows rather than a
        // lone spinner — and the retry re-reads the same product at whatever
        // radius the customer has already widened to.
        loading: () => ListLoadingView(
          message: 'Finding shops near you…',
          // Offer cards: a shop photo, its name and distance, and the price on
          // the right — the product-card silhouette.
          shape: SkeletonRowShape.product,
          onRetry: () =>
              ref.invalidate(productDetailsProvider(widget.productId)),
        ),
        // Was `message: '$err'`, which printed the raw exception as the body. The
        // headline already says what failed, so only the safe message rides
        // along. `fromApi` also hides Retry for a 404/403/422, where retrying
        // could never work.
        error: (err, stack) => ErrorState.fromApi(
          err,
          title: 'Unable to load nearby shops',
          onRetry: () =>
              ref.refresh(productDetailsProvider(widget.productId)),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ProductDetails details) {
    final offers =
        details.shopOffers.where((offer) {
          return !_inStockOnly || offer.isAvailable;
        }).toList()..sort((a, b) {
          switch (_sort) {
            case _ShopSort.lowestPrice:
              return a.price.compareTo(b.price);
            case _ShopSort.highestRated:
              return b.rating.compareTo(a.rating);
            case _ShopSort.nearest:
              return a.distanceInKm.compareTo(b.distanceInKm);
          }
        });

    if (offers.isEmpty) {
      // The VALUE, not the notifier: watching `p.notifier` hands back a stable
      // object, so a radius change would never repaint this control and the
      // label would keep advertising a step it can no longer take.
      final radiusKm = ref.watch(productSearchRadiusProvider);
      return EmptyStateView(
        icon: Icons.storefront_outlined,
        title: _inStockOnly
            ? 'No shops report this item in stock'
            : 'No nearby shops found',
        message: _inStockOnly
            ? 'Try showing all shops or refresh before visiting. Inventory can change quickly.'
            : 'This product is not currently available at any nearby shop.',
        actionLabel: _inStockOnly ? 'Show all shops' : null,
        onActionTap: _inStockOnly
            ? () => setState(() => _inStockOnly = false)
            : null,
        // Only for a genuine "no shops nearby". With the in-stock filter on the
        // customer already has a local recovery above, and offering a radius
        // step alongside it would be two different diagnoses of one symptom.
        actions: _inStockOnly
            ? const []
            : [
                if (canWidenDiscoveryRadius(radiusKm))
                  EmptyStateAction(
                    key: const Key('productNearbySearchWider'),
                    icon: Icons.radar_outlined,
                    label: nextDiscoveryRadiusLabel(radiusKm),
                    onTap: () =>
                        ref.read(productSearchRadiusProvider.notifier).widen(),
                  ),
                EmptyStateAction(
                  key: const Key('productNearbyChangeLocation'),
                  icon: Icons.place_outlined,
                  label: 'Change location',
                  onTap: () => context.push('/select-location'),
                ),
                EmptyStateAction(
                  key: const Key('productNearbySearchAnotherArea'),
                  icon: Icons.pin_drop_outlined,
                  label: 'Search another area',
                  onTap: () => showAreaPinDialog(
                    context,
                    onPin: (pin) => context.push('/search-results-by-pin/$pin'),
                  ),
                ),
              ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      itemCount: offers.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                ChoiceChip(
                  label: const Text('Nearest'),
                  selected: _sort == _ShopSort.nearest,
                  onSelected: (_) => setState(() => _sort = _ShopSort.nearest),
                ),
                ChoiceChip(
                  label: const Text('Lowest price'),
                  selected: _sort == _ShopSort.lowestPrice,
                  onSelected: (_) =>
                      setState(() => _sort = _ShopSort.lowestPrice),
                ),
                ChoiceChip(
                  label: const Text('Top rated'),
                  selected: _sort == _ShopSort.highestRated,
                  onSelected: (_) =>
                      setState(() => _sort = _ShopSort.highestRated),
                ),
                FilterChip(
                  label: const Text('In stock only'),
                  selected: _inStockOnly,
                  onSelected: (value) => setState(() => _inStockOnly = value),
                ),
              ],
            ),
          );
        }
        // A stock reading is a snapshot, not a reservation — say so once,
        // directly above the list the customer is about to act on.
        if (index == 1) {
          return const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.md),
            child: FreshnessDisclaimer(),
          );
        }
        final offer = offers[index - 2];
        return _NearbyShopCard(offer: offer);
      },
    );
  }
}

enum _ShopSort { nearest, lowestPrice, highestRated }

class _NearbyShopCard extends StatelessWidget {
  final ShopInventoryOffer offer;
  const _NearbyShopCard({required this.offer});

  String _formatFreshness(DateTime lastUpdated) {
    // Shared canonical formatter — identical wording to the search result card
    // and the Shop Inventory section, so the same data never reads differently.
    return formatFreshnessText(
      lastUpdated,
      backendStatus: offer.freshnessStatus,
    );
  }

  bool _isStale(DateTime lastUpdated) {
    return isFreshnessWarning(_formatFreshness(lastUpdated));
  }

  String _availabilityLabel() {
    if (!offer.isAvailable) return 'Out of Stock';
    if (_isStale(offer.lastUpdated)) return 'Check stock';
    return 'In Stock';
  }

  @override
  Widget build(BuildContext context) {
    final stale = _isStale(offer.lastUpdated);
    final availabilityLabel = _availabilityLabel();

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
                              '${offer.distanceInKm} km away • ⭐ ${offer.rating}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Backend's opening-hours verdict; unknown renders
                          // nothing so "Open" is never assumed.
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
                        availabilityLabel,
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
      ),
    );
  }
}
