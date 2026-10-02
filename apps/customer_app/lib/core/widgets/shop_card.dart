import 'package:flutter/material.dart';

import '../../features/home/domain/models/home_data.dart';
import '../theme/app_theme.dart';
import 'network_image_view.dart';
import 'shop_open_closed_badge.dart';

/// The discovery card for one shop (Master Spec: Shop Discovery / Shop Card).
///
/// ONE card serves Nearby Shops, Category Shops and Saved Shops. Three
/// near-copies of the same card would drift — one growing an "Open" badge, one
/// not — and a customer would learn a different meaning for the same shop
/// depending on which row they found it in.
///
/// What it shows, and nothing more: image, name, rating, distance, open/closed,
/// verification. Deliberately NOT a shop profile in miniature — the card's one
/// job is to be worth tapping, and [contextLabel] is the only extra line,
/// rendered only when a caller genuinely has context (a price for a product
/// being compared, an availability count for a restaurant).
class ShopCard extends StatelessWidget {
  final Shop shop;
  final VoidCallback onTap;

  /// Overrides [Shop.contextLabel] for callers whose context is only known at the
  /// point of display (e.g. "from ₹120" while comparing one product across
  /// shops). Null falls back to the model's own label, and no label at all
  /// renders no line.
  final String? contextLabel;

  const ShopCard({
    super.key,
    required this.shop,
    required this.onTap,
    this.contextLabel,
  });

  @override
  Widget build(BuildContext context) {
    // Decided once. A caller passing [contextLabel] knows something the model
    // does not, so it wins.
    final label = _nonEmpty(contextLabel) ?? _nonEmpty(shop.contextLabel);
    final rating = shop.rating;
    final distance = shop.distance;
    return Semantics(
      button: true,
      container: true,
      // "View Shop" is the CTA, so it is announced as one, on a node of its own.
      //
      // No MergeSemantics, and deliberately no `excludeSemantics: true`: the
      // children's text stays in the tree, so a screen-reader user still hears the
      // rating, distance and open/closed state — the facts the card exists to
      // communicate. Wrapping this in MergeSemantics was tried and removed: it
      // pushed the label up to an ancestor node, leaving the card's own semantics
      // empty, which is worse than the duplicate announcement it was meant to fix.
      label: 'View shop ${shop.name}',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 200,
          margin: const EdgeInsets.only(right: AppSpacing.md),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  NetworkImageView(
                    imageUrl: shop.imageUrl,
                    height: 100,
                    borderRadius: 12,
                  ),
                  if (shop.isVerified)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.secondary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified, size: 12, color: Colors.white),
                            SizedBox(width: 2),
                            Text(
                              'Verified',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // The visible half of the "View Shop" CTA.
                  //
                  // Deliberately a chevron on the image and NOT a second button:
                  // the whole card is the tap target, and a competing control is
                  // the "overloading" failure the spec warns about. This only makes
                  // the existing affordance legible — no extra layout height, no
                  // extra words on a card that is already carrying six facts.
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            shop.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        // Renders NOTHING when the backend reported no verdict: an
                        // unstated state is never shown as "Open".
                        ShopOpenClosedBadge(
                          isOpenNow: shop.isOpenNow,
                          acceptingOrders: shop.isAcceptingOrders,
                          dense: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        // No ratings yet reads as "New" rather than a confident
                        // 0.0, which would look like a terrible shop.
                        if (rating > 0) ...[
                          const Icon(Icons.star, size: 14, color: Colors.amber),
                          const SizedBox(width: 2),
                          Text(
                            rating.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ] else
                          const Text(
                            'New',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                        const SizedBox(width: AppSpacing.sm),
                        // A distance of 0 means "not known" in this API's
                        // contract (the backend sends 0.0 when the customer's or
                        // the shop's coordinates are missing), so the chip is
                        // omitted rather than printing a confident "0.0 km"
                        // that reads as "you are standing in it".
                        if (distance > 0) ...[
                          const Icon(
                            Icons.location_on,
                            size: 14,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(
                              '${distance.toStringAsFixed(1)} km',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                        ] else
                          const Spacer(),
                      ],
                    ),
                    // The only optional line on the card, and it appears only
                    // when the caller has real context for this shop.
                    if (label != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Treats a blank string as absent, so a caller passing `''` cannot reserve a
  /// line of the card for nothing.
  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}
