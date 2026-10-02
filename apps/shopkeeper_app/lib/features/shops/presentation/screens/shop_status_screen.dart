import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_text.dart';
import '../../domain/shop_models.dart';
import '../controllers/shop_profile_controller.dart';
import '../widgets/shop_profile_shared.dart';

/// Shop Status â€” verification, subscription and order acceptance, all read
/// from the ONE `GET /shopkeeper/shops/{id}` payload the whole Shop Profile
/// module already loads (`shopProfileDetailProvider`). Nothing is derived:
/// every chip/timestamp is a server value, humanized for display.
///
/// This is the screen the Shop Profile hub's "Shop status" tile opens â€” it
/// was declared (`Routes.shopStatus`) and described in the domain model's
/// doc comment but never built, which left the tile dead.
class ShopStatusScreen extends ConsumerStatefulWidget {
  const ShopStatusScreen({super.key});

  @override
  ConsumerState<ShopStatusScreen> createState() => _ShopStatusScreenState();
}

class _ShopStatusScreenState extends ConsumerState<ShopStatusScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (ref.read(shopProfileDetailProvider).status !=
          ShopProfileStatus.ready) {
        ref.read(shopProfileDetailProvider.notifier).load();
      }
    });
  }

  /// `2026-09-17T10:20:00Z` â†’ local short form. Missing/invalid â†’ `â€”`.
  String _stamp(String? iso) {
    if (iso == null || iso.isEmpty) return 'â€”';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(shopProfileDetailProvider);
    return Scaffold(
      appBar: AppBar(title: Text(appText(context).commonShopStatus)),
      body: SafeArea(
        child: ShopModuleBody(
          state: state,
          onRetry: () => ref.read(shopProfileDetailProvider.notifier).load(),
          builder: _buildContent,
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, ShopDetail detail) {
    final verification = detail.verification;
    final subscription = detail.subscription;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(appText(context).commonVerification, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Card(
          key: const Key('shop-status-verification'),
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    shopStatusChip(verification.status),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        appText(context).commonShopVerification,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if ((verification.reviewNotes ?? '').isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    verification.reviewNotes!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const Divider(height: 24),
                ShopInfoRow(label: appText(context).commonSubmitted, value: _stamp(verification.submittedAt)),
                ShopInfoRow(label: appText(context).commonReviewed, value: _stamp(verification.reviewedAt)),
                ShopInfoRow(label: appText(context).commonVerified, value: _stamp(verification.verifiedAt)),
                ShopInfoRow(label: appText(context).commonExpires, value: _stamp(verification.expiresAt)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(appText(context).commonSubscription2, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Card(
          key: const Key('shop-status-subscription'),
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                shopStatusChip(
                  subscription.status,
                  labelOverride:
                      subscription.hasSubscription ? null : 'No plan',
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    subscription.hasSubscription
                        ? (subscription.plan ?? 'Plan')
                        : 'No active subscription',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(appText(context).commonOrders, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Card(
          key: const Key('shop-status-orders'),
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      detail.isAcceptingOrders
                          ? Icons.check_circle_outline
                          : Icons.pause_circle_outline,
                      color: detail.isAcceptingOrders
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        detail.isAcceptingOrders
                            ? 'Accepting orders'
                            : 'Not accepting orders',
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                ShopInfoRow(label: appText(context).commonDelivery, value: detail.isDeliveryAvailable ? 'Available' : 'Off'),
                ShopInfoRow(label: appText(context).commonPickup, value: detail.isPickupAvailable ? 'Available' : 'Off'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
