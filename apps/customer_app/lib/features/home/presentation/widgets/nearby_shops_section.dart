import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/shop_card.dart';
import '../controllers/home_radius_controller.dart';
import 'no_nearby_shops_actions.dart';
import '../../domain/models/home_data.dart';

/// Nearby shop discovery row. Shows an empty state with a search CTA
/// when no nearby shops are available.
///
/// When the list is empty the state offers the recoveries the backend
/// genuinely answers: a wider-area re-read (`radius_km` on `/home/feed`),
/// a fresh GPS fix (`LocationController.refreshLocation`), and a different
/// area (`/search-results-by-pin/:pin`). A recovery offered here is a contract —
/// it is never merely a navigation to a screen that can do nothing.
class NearbyShopsSection extends ConsumerWidget {
  final List<Shop> shops;

  const NearbyShopsSection({super.key, required this.shops});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (shops.isEmpty) {
      // The VALUE is watched, not the notifier: `ref.watch(p.notifier)` hands
      // back a stable object, so a radius change would never notify this widget
      // and the label would keep advertising a step it can no longer take.
      final radiusKm = ref.watch(homeSearchRadiusProvider);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Nearby Shops'),
          // The three recoveries the backend actually answers — widen the
          // query, change the location, search a different area — and nothing
          // else. The generic "Search Products" link that used to sit here was
          // removed rather than kept beside them: it does not recover this empty
          // result, it abandons it, and an empty state that offers an exit
          // instead of a recovery is not an empty state worth rendering.
          NoNearbyShopsActions(
            radiusKm: radiusKm,
            keyPrefix: 'nearby',
            onWidenRadius: () =>
                ref.read(homeSearchRadiusProvider.notifier).widen(),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Nearby Shops',
          actionLabel: 'View All',
          onActionTap: () => context.push('/search'),
        ),
        SizedBox(
          // Taller than the plain card row: the shared card carries an optional
          // context line, and a fixed height that is too short overflows rather
          // than scrolling.
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            itemCount: shops.length,
            itemBuilder: (context, index) {
              final shop = shops[index];
              return ShopCard(
                shop: shop,
                onTap: () => context.push('/shop/${shop.id}'),
              );
            },
          ),
        ),
      ],
    );
  }
}
