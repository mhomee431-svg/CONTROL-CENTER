import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/shop_card.dart';
import '../../../saved_and_history/domain/models/storage_models.dart';
import '../../domain/models/home_data.dart';

/// The customer's own saved shops, served from `GET /saved-shops`.
///
/// Hides itself entirely when the customer has saved nothing, so a customer
/// who has not saved a shop never sees a hollow "Saved Shops" header.
///
/// Saved Shops is a DISCOVERY surface (Master Spec), not a bookmark list, so it
/// renders the SAME `ShopCard` as Nearby and Category Shops. It used to have its
/// own private card, which is how a shop ends up showing "Open" in one row and
/// nothing in another.
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
          // Taller than the plain row because the shared card carries an optional
          // context line; a fixed height that is too short overflows instead of
          // scrolling.
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            itemCount: shops.length,
            itemBuilder: (context, index) {
              final shop = shops[index];
              return ShopCard(
                shop: shop.toDiscoveryShop(),
                onTap: () => context.push('/shop/${shop.shopId}'),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Maps a saved shop onto the shared discovery [Shop] card model.
///
/// Lives here rather than on the model because [Shop] belongs to the home
/// feature: putting this in the saved-and-history DOMAIN would make two domains
/// import each other, and the presentation layer is the right place to know how
/// one feature's data is displayed by another's widget.
extension SavedShopItemDiscovery on SavedShopItem {
  Shop toDiscoveryShop() => Shop(
    id: shopId,
    name: name,
    imageUrl: imageUrl,
    // 0 is this API's "distance not known" sentinel, and the card omits the
    // distance chip for it rather than printing a confident "0.0 km".
    distance: distanceKm ?? 0,
    rating: rating,
    isVerified: isVerified,
    isOpenNow: isOpenNow,
    isAcceptingOrders: isAcceptingOrders,
    // The address is the only context this surface has, so it fills the card's
    // optional line — relevant context where it exists, and nothing invented.
    contextLabel: address.trim().isEmpty ? null : address.trim(),
  );
}
