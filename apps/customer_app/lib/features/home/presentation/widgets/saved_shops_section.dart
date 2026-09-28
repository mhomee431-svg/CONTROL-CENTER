import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/network_image_view.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../saved_and_history/domain/models/storage_models.dart';

/// The customer's own saved shops, served from `GET /saved-shops`.
///
/// Hides itself entirely when the customer has saved nothing, so a customer
/// who has not saved a shop never sees a hollow "Saved Shops" header.
class SavedShopsSection extends StatelessWidget {
  final List<SavedShopItem> shops;
  final String title;

  const SavedShopsSection({
    super.key,
    required this.shops,
    this.title = 'Saved Shops',
  });

  @override
  Widget build(BuildContext context) {
    if (shops.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: title,
          actionLabel: 'View All',
          onActionTap: () => context.push('/my-favorites'),
        ),
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            itemCount: shops.length,
            itemBuilder: (context, index) => _SavedShopCard(shop: shops[index]),
          ),
        ),
      ],
    );
  }
}

class _SavedShopCard extends StatelessWidget {
  final SavedShopItem shop;

  const _SavedShopCard({required this.shop});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'View saved shop ${shop.name}',
      child: GestureDetector(
        onTap: () => context.push('/shop/${shop.shopId}'),
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
              NetworkImageView(
                imageUrl: shop.imageUrl,
                height: 100,
                borderRadius: 12,
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shop.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      shop.address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                    if (shop.rating > 0) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        children: [
                          const Icon(
                            Icons.star,
                            size: 14,
                            color: AppColors.secondary,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            shop.rating.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
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
}
