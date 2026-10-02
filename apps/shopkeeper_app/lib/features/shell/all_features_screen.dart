import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_text.dart';
import '../../core/router/route_names.dart';
import '../shops/domain/shop_models.dart';
import 'capabilities_controller.dart';
/// One destination of the Shopkeeper feature map.
class ShopkeeperFeature {
  const ShopkeeperFeature({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.route,
  });

  /// Stable slug — the tile key, so tests and analytics can address a feature
  /// without depending on its display copy.
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final String route;

  Key get tileKey => Key('feature-tile-$id');
}

/// The complete Shopkeeper feature map — the "Main Shopkeeper Features" block
/// of the product journey, in one navigable place.
///
/// Every entry deep-links to the screen that owns that feature's backend data;
/// the hub itself renders no business numbers. "Imports / POS" is split into
/// its own destinations — the single-screen Excel import ("Import from Excel"),
/// the guided Import Center flow, and the POS integration — because they are
/// separate screens with separate backends.
const List<ShopkeeperFeature> kShopkeeperFeatures = <ShopkeeperFeature>[
  ShopkeeperFeature(
    id: 'dashboard',
    title: 'Dashboard',
    subtitle: 'Today\'s business overview',
    icon: Icons.dashboard_outlined,
    route: Routes.dashboard,
  ),
  ShopkeeperFeature(
    id: 'products',
    title: 'Products',
    subtitle: 'Catalog, pricing & publishing',
    icon: Icons.inventory_2_outlined,
    route: Routes.products,
  ),
  ShopkeeperFeature(
    id: 'inventory',
    title: 'Inventory',
    subtitle: 'Stock health, freshness & adjustments',
    icon: Icons.warehouse_outlined,
    route: Routes.inventoryDashboard,
  ),
  ShopkeeperFeature(
    id: 'offers',
    title: 'Pricing & Offers',
    subtitle: 'Discounts & promotional pricing',
    icon: Icons.local_offer_outlined,
    route: Routes.offers,
  ),
  ShopkeeperFeature(
    id: 'imports',
    title: 'Import from Excel',
    subtitle: 'Upload a filled workbook & review every row',
    icon: Icons.upload_file_outlined,
    route: Routes.inventoryImport,
  ),
  ShopkeeperFeature(
    id: 'import-center',
    title: 'Import Center',
    subtitle: 'Sample workbook, guided upload & history',
    icon: Icons.cloud_upload_outlined,
    route: Routes.importCenter,
  ),
  ShopkeeperFeature(
    id: 'pos',
    title: 'POS integration',
    subtitle: 'Connect & sync a point of sale',
    icon: Icons.point_of_sale_outlined,
    route: Routes.pos,
  ),
  ShopkeeperFeature(
    id: 'insights',
    title: 'Reports / Insights',
    subtitle: 'Customer activity & trends',
    icon: Icons.insights_outlined,
    route: Routes.insights,
  ),
  ShopkeeperFeature(
    id: 'shop-profile',
    title: 'Shop Profile',
    subtitle: 'Public shop details & verification',
    icon: Icons.storefront_outlined,
    route: Routes.shopProfile,
  ),
  ShopkeeperFeature(
    id: 'notifications',
    title: 'Notifications',
    subtitle: 'Alerts, approvals & updates',
    icon: Icons.notifications_outlined,
    route: Routes.notifications,
  ),
  ShopkeeperFeature(
    id: 'settings',
    title: 'Settings',
    subtitle: 'Shop & account preferences',
    icon: Icons.tune,
    route: Routes.shopSettings,
  ),
  ShopkeeperFeature(
    id: 'support',
    title: 'Support',
    subtitle: 'Help center & contact',
    icon: Icons.help_outline,
    route: Routes.support,
  ),
];

/// "All features" — the Shopkeeper Home hub that makes every feature of the
/// journey reachable from one screen.
///
/// Capability-gated (spec section 103): the four backend-driven `canX` flags
/// decide which tiles render. No plan logic lives here - [capabilities]
/// comes from the ONE centralized provider. Backend stays authoritative:
/// a stale permit still meets the server 403, surfaced with the upgrade copy.
class AllFeaturesScreen extends ConsumerWidget {
  const AllFeaturesScreen({super.key, this.capabilities = const ShopCapabilities()});

  /// Flags to gate with. Callers pass the dashboard / shop-detail flags;
  /// default is the permissive legacy set (never locks out on old payloads).
  final ShopCapabilities capabilities;

  void _open(BuildContext context, ShopkeeperFeature feature) {
    // The dashboard IS the shell root, so it is a location change; every other
    // feature is pushed on top of the current stack.
    if (feature.id == 'dashboard') {
      context.go(feature.route);
      return;
    }
    context.push(feature.route);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    // Centralized flags win over the constructor value when the provider has
    // fresher data; the constructor covers direct navigation / tests.
    final caps = ref.watch(capabilitiesControllerProvider);
    final effective = caps == const ShopCapabilities()
        ? capabilities
        : caps;
    final visible = [
      for (final feature in kShopkeeperFeatures)
        if (_isAllowed(feature.id, effective)) feature,
    ];
    return Scaffold(
      appBar: AppBar(title: Text(appText(context).commonAllFeatures3)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              appText(context).allFeaturesScreenEverythingYouManageInOne,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              appText(context).allFeaturesScreenEachScreenShowsLiveData,
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
            const SizedBox(height: 12),
            Card(
              clipBehavior: Clip.antiAlias,
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < visible.length; i++) ...[
                    if (i > 0)
                      Divider(height: 1, color: Theme.of(context).dividerColor),
                    ListTile(
                      key: visible[i].tileKey,
                      leading: Icon(
                        visible[i].icon,
                        color: scheme.primary,
                      ),
                      title: Text(visible[i].title),
                      subtitle: Text(
                        visible[i].subtitle,
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(context, visible[i]),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              appText(context).allFeaturesScreenBusinessScreensOpenOnceYour,
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
          ],
        ),
      ),
    );
  }

  /// Maps hub tiles to the ONE backend flag that gates them. Ungated tiles
  /// (dashboard, products, inventory, profile, notifications, settings,
  /// support) always render.
  static bool _isAllowed(String id, ShopCapabilities caps) {
    switch (id) {
      case 'pos':
        return caps.canUsePos;
      case 'imports':
      case 'import-center':
        return caps.canUploadExcel;
      case 'offers':
        return caps.canCreateOffers;
      case 'insights':
        return caps.canViewReports;
      default:
        return true;
    }
  }
}
