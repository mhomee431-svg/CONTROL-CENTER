import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../domain/dashboard_models.dart';
import '../controllers/dashboard_controller.dart';
import '../../../shops/domain/shop_models.dart'
    show VerificationInfo;
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
        () => ref.read(dashboardControllerProvider.notifier).load());
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
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(shop?.name ?? 'Dashboard',
                style: const TextStyle(fontSize: 18)),
            Text('Business dashboard',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline)),
          ],
        ),
        actions: [
          IconButton(
              tooltip: 'Switch shop',
              onPressed: () => context.push('/shops'),
              icon: const Icon(Icons.swap_horiz)),
        ],
      ),
      body: SafeArea(
        child: switch (state.status) {
          DashboardStatus.loading =>
            const Center(child: CircularProgressIndicator()),
          DashboardStatus.accessDenied => _AccessDeniedView(
              message:
                  state.message ?? 'You do not have access to this shop.',
            ),
          DashboardStatus.error => _ErrorView(
              message: state.message ?? 'Something went wrong.',
              onRetry: () =>
                  ref.read(dashboardControllerProvider.notifier).load(),
            ),
          DashboardStatus.ready => RefreshIndicator(
              onRefresh: () =>
                  ref.read(dashboardControllerProvider.notifier).load(),
              child: _DashboardBody(data: state.data!),
            ),
        },
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 900 ? 4 : 2;
      final ratio = constraints.maxWidth >= 900 ? 2.8 : 1.65;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!data.isVerified)
            _VerificationBanner(verification: data.verification),
          GridView.count(
            crossAxisCount: columns,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
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
                subText: '${data.offers.draft} draft · ${data.offers.total} total',
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
              subtitle: Text(data.subscription.hasSubscription
                  ? '${data.subscription.plan ?? 'Plan'} · ${data.subscription.status}'
                  : 'No active plan'),
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
          Text('Recent updates', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (data.recentUpdates.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Nothing yet — updates will appear here.',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.outline)),
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
    });
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
        child: Row(children: [
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
        ]),
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
  });

  final IconData icon;
  final String label;
  final String value;
  final String subText;

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
            Row(children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        color: scheme.outline,
                        fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            Text(subText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: scheme.outline)),
          ],
        ),
      ),
    );
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
            Row(children: [
              Icon(Icons.warehouse_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Inventory status',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        color: scheme.outline,
                        fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 8),
            _row('In stock', stats.inStock, AppTheme.verifiedGreen, context),
            _row('Low stock', stats.lowStock, AppTheme.pendingAmber, context),
            _row('Out of stock', stats.outOfStock, AppTheme.rejectedRed, context),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, int count, Color color, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
        Text('$count',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      ]),
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
    return Column(children: [
      ListTile(
        dense: true,
        leading: Icon(_icon, size: 20),
        title: Text(update.label, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: update.quantity != null
            ? Text('qty ${update.quantity}',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline))
            : null,
      ),
      if (showDivider)
        Divider(height: 1, color: Theme.of(context).dividerColor),
    ]);
  }
}

class _AccessDeniedView extends StatelessWidget {
  const _AccessDeniedView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.gpp_bad_outlined,
                size: 64, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text('No access to this shop',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.outline)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => context.push('/shops'),
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Switch shop'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

