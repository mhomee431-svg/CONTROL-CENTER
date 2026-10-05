import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../core/router/route_names.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../domain/shop_models.dart';
import '../controllers/shop_profile_controller.dart';
import '../widgets/shop_profile_shared.dart';
import '../widgets/verification_badge.dart';

/// Shop Profile — the module hub: who the shop is, then navigable tiles for
/// every part of it (Edit shop, Business information, Business category,
/// Operating hours, Shop location, Shop status) plus the operational settings.
class ShopProfileScreen extends ConsumerStatefulWidget {
  const ShopProfileScreen({super.key});

  @override
  ConsumerState<ShopProfileScreen> createState() => _ShopProfileScreenState();
}

class _ShopProfileScreenState extends ConsumerState<ShopProfileScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(shopProfileDetailProvider.notifier).load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Switching businesses re-scopes the module to the newly selected shop.
    ref.listen(selectedShopProvider, (prev, next) {
      if (prev?.id != next?.id) {
        ref.read(shopProfileDetailProvider.notifier).load();
      }
    });

    final state = ref.watch(shopProfileDetailProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(appText(context).commonShopProfile4),
        actions: [
          IconButton(
            key: const Key('shop-profile-refresh'),
            tooltip: appText(context).commonRefresh8,
            onPressed: () =>
                ref.read(shopProfileDetailProvider.notifier).load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ShopModuleBody(
          state: state,
          onRetry: () => ref.read(shopProfileDetailProvider.notifier).load(),
          builder: (context, detail) => RefreshIndicator(
            onRefresh: () =>
                ref.read(shopProfileDetailProvider.notifier).load(),
            child: ListView(
              // Always scrollable: pull-to-refresh must fire even when the
              // tiles fit on one screen.
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                _identityCard(context, detail),
                const SizedBox(height: 16),
                ShopSection(
                  title: 'Business',
                  tiles: [
                    ShopHubTile(
                      const Key('shop-tile-edit'),
                      Icons.edit_outlined,
                      'Edit shop',
                      'Name, tagline, description and contact details',
                      Routes.shopEdit,
                    ),
                    ShopHubTile(
                      Key('shop-tile-business-info'),
                      Icons.info_outline,
                      'Business information',
                      'Category, GSTIN, owner and member-since facts',
                      Routes.shopBusinessInfo,
                    ),
                    ShopHubTile(
                      Key('shop-tile-category'),
                      Icons.category_outlined,
                      'Business category',
                      'What your shop sells and what it requires',
                      Routes.shopBusinessCategory,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ShopSection(
                  title: 'Operations',
                  tiles: [
                    ShopHubTile(
                      const Key('shop-tile-hours'),
                      Icons.schedule_outlined,
                      'Operating hours',
                      'Opening times for every weekday',
                      Routes.shopOperatingHours,
                    ),
                    ShopHubTile(
                      const Key('shop-tile-location'),
                      Icons.location_on_outlined,
                      'Shop location',
                      detail.hasLocation
                          ? 'Stored pin: ${detail.coordinatesLabel}'
                          : 'No pin stored yet — add one from GPS',
                      Routes.shopLocationView,
                    ),
                    ShopHubTile(
                      const Key('shop-tile-status'),
                      Icons.flag_outlined,
                      'Shop status',
                      'Verification, subscription and order acceptance',
                      Routes.shopStatus,
                    ),
                    ShopHubTile(
                      const Key('shop-tile-settings'),
                      Icons.tune_outlined,
                      'Shop settings',
                      'Order acceptance, delivery and pickup',
                      Routes.shopSettings,
                    ),
                    // Restaurants only. The backend owns a real menu API and a
                    // restaurant is the only category with one, so this tile is
                    // the whole of that capability's entry point — offered to
                    // every other trade it would be a dead end.
                    // Restaurants only, asked of the registry rather than by writing the code out:
                    // the one home for category codes is shop_models.dart, and a
                    // literal here would be a second copy of it.
                    if (serviceProfileForCategory(
                          detail.summary.category ?? '',
                        ) ==
                        ServiceCategoryProfile.restaurant)
                      ShopHubTile(
                        const Key('shop-tile-menu'),
                        Icons.restaurant_menu,
                        'Menu',
                        'Sections and dishes customers can browse',
                        Routes.restaurantMenu,
                      ),
                  ],
                ),
                if (!shopCanEdit(ref)) ...[
                  const SizedBox(height: 16),
                  const ShopPermissionNotice(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _identityCard(BuildContext context, ShopDetail detail) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    detail.summary.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                VerificationBadge(status: detail.verification.status),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              appText(context).shopProfileScreenValueValue2CategoryLabel(detail.summary.membership == 'owner' ? 'Owner' : 'Manager', humanizeCode(detail.summary.status), detail.categoryLabel),
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
            if ((detail.tagline ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(detail.tagline!, style: const TextStyle(fontSize: 13)),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.phone_outlined, size: 16, color: scheme.outline),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    detail.phone ?? 'No phone added yet',
                    style: TextStyle(fontSize: 12, color: scheme.outline),
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