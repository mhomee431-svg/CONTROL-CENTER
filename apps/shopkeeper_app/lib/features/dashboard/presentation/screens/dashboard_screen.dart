import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/state/system_state.dart';
import '../../../../core/state/system_state_view.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../../products/presentation/widgets/product_sheets.dart'
    show ProductAddMethodSheet;
import '../../../shops/domain/shop_models.dart' show ShopCapabilities;
import '../../../notifications/domain/notification_models.dart';
import '../../../notifications/presentation/controllers/notifications_controller.dart';
import '../../domain/dashboard_models.dart';
import '../controllers/dashboard_controller.dart';
import '../../../shops/domain/shop_models.dart' show VerificationInfo;
import '../../../shops/presentation/widgets/verification_badge.dart';

/// Operational dashboard for the selected shop.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(dashboardControllerProvider.notifier).load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Reload when the shopkeeper switches businesses.
    ref.listen(selectedShopProvider, (prev, next) {
      if (prev?.id != next?.id) {
        ref.read(dashboardControllerProvider.notifier).load();
      }
    });

    final state = ref.watch(dashboardControllerProvider);
    final shop = ref.watch(selectedShopProvider);
    final user = ref.watch(authControllerProvider).user;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              shop?.name ?? 'Dashboard',
              style: const TextStyle(fontSize: 18),
            ),
            Text(
              'Business dashboard',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
        actions: [
          // Single-shop model: no business switching. Jump straight to this
          // shop's profile/settings when one exists.
          if (shop != null)
            IconButton(
              tooltip: 'Shop settings',
              onPressed: () => context.push(Routes.shopSettings),
              icon: const Icon(Icons.tune),
            ),
        ],
      ),
      body: SafeArea(
        child: switch (state.status) {
          DashboardStatus.loading => const Center(
            child: CircularProgressIndicator(),
          ),
          DashboardStatus.accessDenied => SystemStateView(
            spec: SystemStateSpec.resolve(
              state: SystemState.permissionDenied,
              title: 'No access to this shop',
              message: state.message,
              fallbackMessage: 'You do not have access to this shop.',
            ),
            onSwitchShop: () => context.push(Routes.shops),
          ),
          DashboardStatus.noShop => const _NoShopView(),
          DashboardStatus.error => SystemStateView(
            spec: SystemStateSpec.resolve(
              message: state.message,
              fallbackMessage: 'Something went wrong.',
            ),
            onRetry: () =>
                ref.read(dashboardControllerProvider.notifier).load(),
          ),
          DashboardStatus.ready => RefreshIndicator(
            // Pull is the SILENT path (DashboardController.refresh): the
            // numbers stay on screen while fresh ones load.
            onRefresh: () =>
                ref.read(dashboardControllerProvider.notifier).refresh(),
            child: _DashboardBody(
              data: state.data!,
              alerts: state.alerts,
              user: user,
              shop: shop,
            ),
          ),
        },
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.data, this.alerts, this.user, this.shop});

  final DashboardData data;

  /// "Needs attention" signals for the priority card (fail-soft).
  final DashboardAlerts? alerts;

  /// Authenticated shopkeeper (for the personalised greeting).
  final dynamic user;

  /// Currently selected shop (name/category/pending verification).
  final dynamic shop;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900 ? 4 : 2;
        const gap = 12.0;
        const outerPadding = 32.0; // ListView horizontal padding (16 × 2)
        final tileWidth =
            (constraints.maxWidth - outerPadding - (columns - 1) * gap) /
            columns;
        // Keep stat cards tall enough for their content at every width
        // (fixed ratios overflowed on wide screens).
        final ratio = math.max(1.35, tileWidth / 112);
        return ListView(
          // Always scrollable: pull-to-refresh must fire even when the cards
          // fit on one screen.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            // Shopkeeper Home header — greeting + shop summary + quick actions.
            _HomeHeader(
              user: user,
              shop: shop,
              capabilities: data.capabilities,
            ),
            // Dashboard notifications — the newest updates for this shop, read
            // from the Alerts controller (single source of truth) so Home and
            // the Alerts tab can never disagree. Hides itself when empty/failed.
            const _RecentNotificationsStrip(),
            // "Needs attention" priorities (req 21) — only real, loaded data
            // is surfaced; the card stays hidden when everything looks fine.
            _PriorityCard(data: data, alerts: alerts),
            if (!data.isVerified)
              _VerificationBanner(verification: data.verification),
            // Overview section header — the stat grid below is the daily read.
            Text(
              'Overview',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: columns,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: gap,
              crossAxisSpacing: gap,
              childAspectRatio: ratio,
              children: [
                _StatCard(
                  icon: Icons.inventory_2_outlined,
                  label: 'Products',
                  value: '${data.products.total}',
                  subText:
                      '${data.products.active} active · ${data.products.inactive} inactive',
                ),
                _StatCard(
                  icon: Icons.check_circle_outline,
                  label: 'Active products',
                  value: '${data.products.active}',
                  subText: 'visible to customers',
                ),
                _InventoryCard(stats: data.products),
                _StatCard(
                  icon: Icons.local_offer_outlined,
                  label: 'Offers',
                  value: '${data.offers.active} active',
                  subText:
                      '${data.offers.draft} draft · ${data.offers.total} total',
                  // Offers live on the product listings — deep-link there
                  // where the create-offer sheet is reachable.
                  onTap: () => context.push(Routes.products),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: Icon(
                  data.subscription.isActive
                      ? Icons.workspace_premium
                      : Icons.upcoming_outlined,
                  color: data.subscription.isActive
                      ? AppTheme.verifiedGreen
                      : Theme.of(context).colorScheme.outline,
                ),
                title: const Text('Subscription'),
                subtitle: Text(
                  data.subscription.hasSubscription
                      ? '${data.subscription.plan ?? 'Plan'} · ${data.subscription.status}'
                      : 'No active plan',
                ),
                trailing: Text(
                  data.subscription.status,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: data.subscription.isActive
                        ? AppTheme.verifiedGreen
                        : Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Recent updates',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (data.recentUpdates.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Nothing yet — updates will appear here.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
              )
            else
              Card(
                clipBehavior: Clip.antiAlias,
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < data.recentUpdates.length; i++)
                      _UpdateTile(
                        update: data.recentUpdates[i],
                        showDivider: i < data.recentUpdates.length - 1,
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 32),
          ],
        );
      },
    );
  }
}

/// Shopkeeper Home header — shown above the operational dashboard: a
/// personalised time-aware greeting, the shop summary (name, category,
/// profile status) and quick actions. Every value comes from the
/// authenticated session / selected shop — the backend dashboard cards
/// below remain the source of truth for product & inventory numbers
/// (never faked here).
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({this.user, this.shop, this.capabilities});

  final dynamic user;
  final dynamic shop;

  /// Backend-driven feature flags (spec section 103), passed down from the
  /// dashboard payload - the ONE source the quick-action tiles gate on.
  /// Absent (old payloads) -> permissive default, never a lock-out.
  final ShopCapabilities? capabilities;

  ShopCapabilities get _caps => capabilities ?? const ShopCapabilities();

  /// Shopkeeper's first name for the greeting (falls back to a generic
  /// "Shopkeeper" when the Google profile has no name yet).
  String get _firstName {
    final name = (user?.displayName as String?)?.trim() ?? '';
    return name.isEmpty ? 'Shopkeeper' : name.split(' ').first;
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  /// Human-readable label for an approved merchant-category code.
  /// Unknown codes fall back to the raw code — never a guessed label.
  static String _categoryLabel(String? code) {
    return switch (code) {
      'PHARMACY_HEALTHCARE' => 'Pharmacy & Healthcare',
      'BEAUTY_PERSONAL_CARE' => 'Beauty & Personal Care',
      'FURNITURE_HOME_CARE' => 'Furniture & Home Care',
      'HOUSEHOLD_GOODS' => 'Household Goods',
      'SPORTS_FITNESS_OUTDOOR' => 'Sports, Fitness & Outdoor',
      'BOOKS_MEDIA_STATIONERY' => 'Books, Media & Stationery',
      'AUTOMOTIVE_PARTS_TOOLS' => 'Automotive Parts & Tools',
      'HARDWARE' => 'Hardware',
      'RESTAURANTS' => 'Restaurants',
      'TRANSPORT' => 'Transport',
      'PERSONAL_TRANSPORT_TRAVEL' => 'Personal Transport / Personal Travel',
      _ => code ?? 'Not set',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$_greeting, $_firstName',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Welcome back to your business dashboard.',
          style: TextStyle(fontSize: 13, color: scheme.outline),
        ),
        const SizedBox(height: 16),
        // ── Shop summary (authenticated session data — never faked) ──
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow(context, Icons.storefront, 'Shop', shop?.name),
                _infoRow(
                  context,
                  Icons.category_outlined,
                  'Category',
                  _categoryLabel(shop?.category as String?),
                ),
                _infoRow(
                  context,
                  Icons.badge_outlined,
                  'Profile Status',
                  'Profile Created',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Quick Actions',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        // Quick actions are navigation targets; the linked screens own the
        // real backend data — nothing is fabricated on this home.
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _QuickAction(
              icon: Icons.add_box_outlined,
              label: 'Add Product',
              color: scheme.primary,
              // Req 24: every Add affordance goes through the method
              // chooser (manual / barcode / bulk Excel) — consistent
              // with the Products screen FAB.
              onTap: () => showModalBottomSheet<void>(
                context: context,
                builder: (_) => const ProductAddMethodSheet(),
              ),
            ),
            _QuickAction(
              icon: Icons.inventory_2_outlined,
              label: 'Inventory',
              color: AppTheme.verifiedGreen,
              // Inventory owns its own module hub (stock health, freshness,
              // adjustments, history) — open that, not the product catalog.
              onTap: () => context.push(Routes.inventoryDashboard),
            ),
            _QuickAction(
              icon: Icons.local_offer_outlined,
              label: 'Pricing & Offers',
              color: AppTheme.pendingAmber,
              // Capability-gated (spec section 103): hidden when the backend
              // flag says the plan cannot create offers. The flag comes from
              // the centralized backend derivation - no plan logic here.
              visible: _caps.canCreateOffers,
              // Pricing & Offers owns discounts / promo pricing (the
              // create-offer sheet is also reachable from Products).
              onTap: () => context.push(Routes.offers),
            ),
            _QuickAction(
              icon: Icons.insights_outlined,
              label: 'Reports & Insights',
              color: scheme.tertiary,
              visible: _caps.canViewReports,
              // Reports / Insights is backed by the shop analytics
              // endpoints — real customer activity, never local guesses.
              onTap: () => context.push(Routes.insights),
            ),
            _QuickAction(
              icon: Icons.storefront_outlined,
              label: 'Shop Profile',
              color: scheme.secondary,
              onTap: () => context.push(Routes.shopProfile),
            ),
            _QuickAction(
              icon: Icons.apps,
              label: 'All Features',
              color: scheme.primary,
              // The complete feature map (dashboard, imports/POS, support,
              // settings, …) in one hub.
              onTap: () => context.push(Routes.features),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _infoRow(
    BuildContext context,
    IconData icon,
    String label,
    String? value,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$label: ${value ?? 'Not set'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// Touch-friendly quick-action tile (icon tile with label + ripple).
class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.visible = true,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  /// Capability gate (spec section 103): false hides the tile. Driven ONLY
  /// by the backend `canX` flag - never by local plan logic.
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: label,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 140,
          height: 88,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 24, color: color),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Needs attention" priority card (req 21).
///
/// Fixed order: low stock, failed import, stale inventory, important
/// notification, profile/setup issue. Only rows backed by real data are
/// rendered — nothing is fabricated client-side; when no priority has data
/// the card is not shown at all.
class _PriorityCard extends StatelessWidget {
  const _PriorityCard({required this.data, this.alerts});

  final DashboardData data;
  final DashboardAlerts? alerts;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final alert = alerts;
    // The backend's own sorted needs_attention list (OUT_OF_STOCK first)
    // names the exact products to fix — surface up to 3 of them.
    final flagged = data.products.needsAttention;
    final flaggedLabel = flagged.isEmpty
        ? ''
        : ' — ${flagged.take(3).map((p) => p.name).join(', ')}'
              '${flagged.length > 3 ? ' +${flagged.length - 3} more' : ''}';
    final rows = <_PriorityRow>[
      if (data.products.lowStock + data.products.outOfStock > 0)
        _PriorityRow(
          icon: Icons.warning_amber_outlined,
          color: AppTheme.pendingAmber,
          title: 'Low stock',
          subtitle:
              '${data.products.lowStock} low '
              '${data.products.outOfStock > 0 ? '· ${data.products.outOfStock} out of stock' : ''}'
              '$flaggedLabel',
          route: Routes.products,
        ),
      if (alert != null && alert.hasFailedImport)
        _PriorityRow(
          icon: Icons.error_outline,
          color: scheme.error,
          title: 'Failed import',
          subtitle:
              '${alert.failedImportName} — ${alert.failedImportRows} row(s) '
              'could not be applied',
          route: Routes.inventoryImport,
        ),
      if (alert != null && alert.staleCount > 0)
        _PriorityRow(
          icon: Icons.hourglass_bottom_outlined,
          color: scheme.tertiary,
          title: 'Inventory stale',
          subtitle: '${alert.staleCount} product(s) not updated in a while',
          route: Routes.products,
        ),
      if (alert != null && alert.unreadNotifications > 0)
        _PriorityRow(
          icon: Icons.notifications_active_outlined,
          color: scheme.primary,
          title: 'Important notification',
          subtitle: '${alert.unreadNotifications} unread notification(s)',
          route: Routes.notifications,
        ),
      if (!data.isVerified)
        _PriorityRow(
          icon: Icons.store_outlined,
          color: scheme.primary,
          title: 'Profile setup issue',
          subtitle: 'Complete shop verification to publish to customers',
          route: Routes.shopSettings,
        ),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Needs attention',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0)
                  Divider(height: 1, indent: 56, color: scheme.outlineVariant),
                rows[i].toTile(context),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// One actionable priority row inside [_PriorityCard].
class _PriorityRow {
  const _PriorityRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String route;

  Widget toTile(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => context.push(route),
    );
  }
}

class _VerificationBanner extends StatelessWidget {
  const _VerificationBanner({required this.verification});

  final VerificationInfo verification;

  @override
  Widget build(BuildContext context) {
    final rejected = verification.isRejected;
    final color = rejected ? AppTheme.rejectedRed : AppTheme.pendingAmber;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            VerificationBadge(status: verification.status, compact: false),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                rejected
                    ? 'Verification rejected${verification.reviewNotes != null ? ' — ${verification.reviewNotes}' : ''}'
                    : 'Your shop is not verified yet. Some features may be limited.',
                style: TextStyle(fontSize: 13, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.subText,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final String subText;

  /// Optional tap target (e.g. Offers → Products management). When null the
  /// card stays purely informational.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final card = Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.outline,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              subText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
          ],
        ),
      ),
    );
    if (onTap == null) return card;
    return InkWell(onTap: onTap, child: card);
  }
}

class _InventoryCard extends StatelessWidget {
  const _InventoryCard({required this.stats});

  final ProductStats stats;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(Icons.warehouse_outlined, size: 18, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Inventory status',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.outline,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _row('In stock', stats.inStock, AppTheme.verifiedGreen, context),
            _row('Low stock', stats.lowStock, AppTheme.pendingAmber, context),
            _row(
              'Out of stock',
              stats.outOfStock,
              AppTheme.rejectedRed,
              context,
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, int count, Color color, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _UpdateTile extends StatelessWidget {
  const _UpdateTile({required this.update, this.showDivider = false});

  final RecentUpdate update;
  final bool showDivider;

  IconData get _icon {
    switch (update.type) {
      case 'stock_update':
        return Icons.sync_alt;
      case 'price_update':
        return Icons.currency_rupee;
      default:
        return Icons.add_box_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          dense: true,
          leading: Icon(_icon, size: 20),
          title: Text(
            update.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: update.quantity != null
              ? Text(
                  'qty ${update.quantity}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                )
              : null,
        ),
        if (showDivider)
          Divider(height: 1, color: Theme.of(context).dividerColor),
      ],
    );
  }
}

/// Friendly landing view shown right after the first login, when the
/// shopkeeper has not created a shop yet. Personal/business setup
/// (name, location, documents) is done here or later from the Profile
/// (Account) section — never forced as a blocking wizard at login.
class _NoShopView extends StatelessWidget {
  const _NoShopView();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: scheme.primaryContainer,
                  child: const Icon(
                    Icons.storefront,
                    size: 40,
                    color: AppColors.deepGreen,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Welcome to Passly Biz!',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Your account is ready. Add your first store to start '
                  'managing products, inventory and offers — or complete '
                  'your profile details from the Account tab anytime.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.outline),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => context.push(Routes.shopRegister),
                  icon: const Icon(Icons.add_box_outlined),
                  label: const Text('Set up your first shop'),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => context.push(Routes.account),
                  icon: const Icon(Icons.person_outline),
                  label: const Text('Complete your profile'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Dashboard notifications" strip on the Shopkeeper Home.
///
/// Reads the SAME single source of truth as the Alerts tab
/// ([notificationsControllerProvider]) instead of fetching its own page — a
/// second copy would drift from the Alerts badge the moment anything is read.
///
/// Fail-soft by design: with nothing to report (or when the load failed) the
/// strip removes itself rather than adding an error to the home screen; the
/// "Needs attention" card owns alerting.
class _RecentNotificationsStrip extends ConsumerWidget {
  const _RecentNotificationsStrip();

  /// Home is a summary — the Alerts tab owns the full history.
  static const _maxItems = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationsControllerProvider);
    final scheme = Theme.of(context).colorScheme;

    if (state.status == NotificationsStatus.error) {
      return const SizedBox.shrink();
    }
    if (state.status == NotificationsStatus.loading) {
      return _NotificationsSkeleton(placeholder: scheme.outlineVariant);
    }
    final items = state.items.take(_maxItems).toList(growable: false);
    if (items.isEmpty) return const SizedBox.shrink();

    final unread = state.unreadCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Recent Updates',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            if (unread > 0)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  '$unread new',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.error,
                  ),
                ),
              ),
            // Alerts is a bottom-navigation destination: `go` switches the
            // shell branch (keeping the tab bar) instead of stacking a page.
            TextButton(
              onPressed: () => context.go(Routes.notifications),
              child: const Text('View all'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0)
                  Divider(height: 1, indent: 56, color: scheme.outlineVariant),
                _NotificationStripRow(notification: items[i]),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// One compact row inside the Home "Dashboard notifications" strip.
class _NotificationStripRow extends ConsumerWidget {
  const _NotificationStripRow({required this.notification});

  final ShopkeeperNotification notification;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final unread = notification.isUnread;

    return ListTile(
      onTap: () {
        // Optimistic mark-as-read through the SSOT controller (the exact call
        // the Alerts tab makes), then open the full list for context.
        ref
            .read(notificationsControllerProvider.notifier)
            .markAsRead(notification.id);
        context.go(Routes.notifications);
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Badge(
        isLabelVisible: unread,
        smallSize: 10,
        child: CircleAvatar(
          backgroundColor: unread
              ? scheme.primaryContainer
              : theme.dividerColor.withValues(alpha: 0.3),
          child: Icon(
            notificationIcon(notification.type),
            size: 20,
            color: unread ? scheme.primary : scheme.outline,
          ),
        ),
      ),
      title: Text(
        notification.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      subtitle: Text(
        notification.body,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: scheme.outline),
      ),
      trailing: Text(
        notificationTimeLabel(notification.createdAt),
        style: TextStyle(fontSize: 11, color: scheme.outline),
      ),
    );
  }
}

/// Placeholder shown while notifications load, so Home never jumps straight
/// from nothing to a full card.
class _NotificationsSkeleton extends StatelessWidget {
  const _NotificationsSkeleton({required this.placeholder});

  final Color placeholder;

  /// Stable handle for widget tests.
  static const skeletonKey = ValueKey('home-notifications-skeleton');

  @override
  Widget build(BuildContext context) {
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: placeholder,
        borderRadius: BorderRadius.circular(4),
      ),
    );

    return Column(
      key: skeletonKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        bar(140, 16),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) Divider(height: 1, indent: 56, color: placeholder),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 2,
                  ),
                  leading: CircleAvatar(backgroundColor: placeholder),
                  title: bar(160, 12),
                  subtitle: bar(220, 10),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
