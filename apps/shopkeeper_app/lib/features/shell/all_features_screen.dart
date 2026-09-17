import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/route_names.dart';

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
class AllFeaturesScreen extends StatelessWidget {
  const AllFeaturesScreen({super.key});

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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('All features')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Everything you manage, in one place',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Each screen shows live data for your selected shop.',
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
            const SizedBox(height: 12),
            Card(
              clipBehavior: Clip.antiAlias,
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < kShopkeeperFeatures.length; i++) ...[
                    if (i > 0)
                      Divider(height: 1, color: Theme.of(context).dividerColor),
                    ListTile(
                      key: kShopkeeperFeatures[i].tileKey,
                      leading: Icon(
                        kShopkeeperFeatures[i].icon,
                        color: scheme.primary,
                      ),
                      title: Text(kShopkeeperFeatures[i].title),
                      subtitle: Text(
                        kShopkeeperFeatures[i].subtitle,
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(context, kShopkeeperFeatures[i]),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Business screens open once your shop is set up.',
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
