import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../auth/domain/auth_models.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../domain/profile_scope.dart';
import '../../domain/shop_models.dart';
import '../controllers/shops_controller.dart';
import '../widgets/verification_badge.dart';

/// Shop details — in the single-shop model the account has at most ONE
/// business. This screen shows that shop (or an invite to set one up).
class ShopsScreen extends ConsumerStatefulWidget {
  const ShopsScreen({super.key});

  @override
  ConsumerState<ShopsScreen> createState() => _ShopsScreenState();
}

class _ShopsScreenState extends ConsumerState<ShopsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(shopsControllerProvider.notifier).load());
  }

  void _select(ShopSummary shop) {
    ref.read(selectedShopProvider.notifier).select(shop);
    context.go(Routes.dashboard);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(shopsControllerProvider);
    final selected = ref.watch(selectedShopProvider);
    // Single-profile MVP: the primary shop is auto-selected after login, so
    // there is nothing left to CHOOSE. The list-and-select picker therefore
    // renders only when the future multi-business switch is on — the same
    // chokepoint `account_screen.dart` and the 403 states read (see
    // profile_scope.dart).
    final multiShop = ref.watch(multiShopEnabledProvider);
    return Scaffold(
      appBar: AppBar(title: Text(appText(context).commonMyBusiness2)),
      body: SafeArea(
        child: state.status == ShopsStatus.loading && state.shops.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                // Pull is the SILENT path (ShopsController.refresh): the list
                // stays on screen while fresh shops load.
                onRefresh: () =>
                    ref.read(shopsControllerProvider.notifier).refresh(),
                child: state.shops.isEmpty
                    ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
                        const SizedBox(height: 120),
                        Icon(Icons.add_business_outlined,
                            size: 64,
                            color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: 12),
                        Center(
                          child: Text(
                            appText(context).shopsScreenNoShopsYetRegisterYour,
                            textAlign: TextAlign.center,
                            style:
                                Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                      ])
                    : ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (!multiShop)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                'Current business',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline,
                                    ),
                              ),
                            ),
                          for (var i = 0; i < state.shops.length; i++) ...[
                            if (i > 0) const SizedBox(height: 8),
                            _ShopTile(
                              shop: state.shops[i],
                              // In the MVP there is no selection to make, so the
                              // tile is read-only: tapping it would only ever
                              // re-select the shop already selected.
                              selected: multiShop
                                  ? selected?.id == state.shops[i].id
                                  : false,
                              onTap: multiShop
                                  ? () => _select(state.shops[i])
                                  : null,
                            ),
                          ],
                        ],
                      ),
              ),
      ),
    );
  }
}

class _ShopTile extends StatelessWidget {
  const _ShopTile({required this.shop, required this.selected, this.onTap});

  final ShopSummary shop;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.mdBorder,
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          child: Text(
            shop.name.isEmpty ? '?' : shop.name[0].toUpperCase(),
            style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700),
          ),
        ),
        title: Text(shop.name,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _chip(context, shop.membership == 'owner' ? 'Owner' : 'Manager',
                  shop.membership == 'owner' ? scheme.primary : scheme.secondary),
              if (shop.category != null)
                _chip(context, shop.category!, scheme.outline),
            ],
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            VerificationBadge(status: shop.isVerified ? 'VERIFIED' : 'PENDING'),
            if (selected)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Icon(Icons.check_circle,
                    size: 16, color: scheme.primary),
              ),
          ],
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: AppRadius.xsBorder,
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600)),
      );
}
