import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/state/system_state.dart';
import '../../../../core/state/system_state_view.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../domain/shop_models.dart';
import '../controllers/shop_profile_controller.dart';

/// Async body for every Shop Profile screen: one spinner / no-shop / error
/// contract, with the ready state handed to [builder].
class ShopModuleBody extends ConsumerWidget {
  const ShopModuleBody({
    super.key,
    required this.state,
    required this.onRetry,
    required this.builder,
  });

  final ShopProfileState state;
  final VoidCallback onRetry;
  final Widget Function(BuildContext context, ShopDetail detail) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (state.status) {
      ShopProfileStatus.loading ||
      ShopProfileStatus.noShop => const Center(
          child: CircularProgressIndicator(),
        ),
      // One shared renderer for every failure: the state's icon/action plus the
      // controller's own message when the server explained itself.
      ShopProfileStatus.error => SystemStateView(
          spec: SystemStateSpec.resolve(
            title: 'Could not load this shop',
            message: state.message,
            fallbackMessage: 'Something went wrong.',
          ),
          onRetry: onRetry,
          retryKey: const Key('shop-retry'),
        ),
      ShopProfileStatus.ready => builder(context, state.detail!),
    };
  }
}

/// One navigable row of a Shop Profile hub.
class ShopHubTile {
  const ShopHubTile(this.key, this.icon, this.title, this.subtitle, this.route);

  final Key key;
  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
}

/// Titled card of hub tiles, matching the inventory + POS hubs.
class ShopSection extends StatelessWidget {
  const ShopSection({super.key, required this.title, required this.tiles});

  final String title;
  final List<ShopHubTile> tiles;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                ListTile(
                  key: tiles[i].key,
                  leading: Icon(
                    tiles[i].icon,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(tiles[i].title),
                  subtitle: Text(
                    tiles[i].subtitle,
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(tiles[i].route),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// `label — value` row used by the read-only information screens.
class ShopInfoRow extends StatelessWidget {
  const ShopInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
  });

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: scheme.outline),
            const SizedBox(width: 8),
          ],
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

/// Colored status chip for shop / verification / subscription states.
class ShopStatusChip extends StatelessWidget {
  const ShopStatusChip({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// Server status → display copy / color. Unknown values never crash and are
/// shown verbatim (humanized), never invented.
ShopStatusChip shopStatusChip(String? status, {String? labelOverride}) {
  final value = (status ?? '').trim().toUpperCase();
  final (String label, Color color) = switch (value) {
    'VERIFIED' || 'ACTIVE' => ('Verified', AppTheme.verifiedGreen),
    'REJECTED' => ('Rejected', AppTheme.rejectedRed),
    'SUSPENDED' || 'BLOCKED' => ('Suspended', AppTheme.rejectedRed),
    'NONE' => ('No plan', AppTheme.pendingAmber),
    _ => (
        value.isEmpty ? 'Pending' : humanizeCode(value),
        AppTheme.pendingAmber,
      ),
  };
  return ShopStatusChip(label: labelOverride ?? label, color: color);
}

/// The read-only notice managers see on every editable screen.
class ShopPermissionNotice extends StatelessWidget {
  const ShopPermissionNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.lock_outline,
            size: 16,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Managers have read-only access here. Ask the shop owner for '
              'changes.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Whether the signed-in member may edit the shop (`update:shop` permission).
bool shopCanEdit(WidgetRef ref) =>
    ref.read(selectedShopProvider)?.canManageSettings ?? false;