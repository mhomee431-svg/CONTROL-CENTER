import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/empty_state_view.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/shop_card.dart';
import '../../domain/models/home_data.dart';

/// Nearby shop discovery row. Shows an empty state with a search CTA
/// when no nearby shops are available.
class NearbyShopsSection extends StatelessWidget {
  final List<Shop> shops;

  const NearbyShopsSection({super.key, required this.shops});

  @override
  Widget build(BuildContext context) {
    if (shops.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Nearby Shops'),
          EmptyStateView(
            icon: Icons.storefront_outlined,
            title: 'No nearby shops found',
            message: 'Try searching for a product to discover shops near you.',
            actionLabel: 'Search Products',
            onActionTap: () => context.push('/search'),
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
          height: 180,
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