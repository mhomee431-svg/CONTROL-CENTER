import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../offers/domain/offer_models.dart';
import '../../../offers/presentation/controllers/offers_controller.dart';

/// Base for the two offer-bucket screens (Active / Expired).
///
/// ONE fetch serves both — `OffersListController` slices the result locally,
/// so switching between the two routes never re-hits the network.
class OfferBucketScreen extends ConsumerStatefulWidget {
  const OfferBucketScreen({super.key, required this.expiredOnly});

  final bool expiredOnly;

  @override
  ConsumerState<OfferBucketScreen> createState() => _OfferBucketScreenState();
}

class _OfferBucketScreenState extends ConsumerState<OfferBucketScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final state = ref.read(offersListControllerProvider);
      if (state.status == OffersListStatus.loading) {
        ref.read(offersListControllerProvider.notifier).load();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(offersListControllerProvider);
    final title = widget.expiredOnly ? 'Expired offers' : 'Active offers';
    final offers = widget.expiredOnly ? state.expiredOffers : state.openOffers;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Create offer',
            icon: const Icon(Icons.add_outlined),
            onPressed: () => context.push(Routes.createOffer),
          ),
        ],
      ),
      body: switch (state.status) {
        OffersListStatus.loading =>
          const Center(child: CircularProgressIndicator()),
        OffersListStatus.noShop => const _Message(
            icon: Icons.storefront_outlined,
            text: 'Select a shop to see its offers.',
          ),
        OffersListStatus.error => _Message(
            icon: Icons.error_outline,
            text: state.message ?? 'Could not load offers.',
            onRetry: () =>
                ref.read(offersListControllerProvider.notifier).load(),
          ),
        OffersListStatus.ready => offers.isEmpty
            ? _Message(
                icon: widget.expiredOnly
                    ? Icons.history_outlined
                    : Icons.local_offer_outlined,
                text: widget.expiredOnly
                    ? 'No expired offers. Offers that finish their window will be listed here.'
                    : 'No offers are running right now. Create one to boost sales.',
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: offers.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 16),
                itemBuilder: (context, i) => _OfferTile(offer: offers[i]),
              ),
      },
    );
  }
}

class _OfferTile extends StatelessWidget {
  const _OfferTile({required this.offer});

  final OfferSummary offer;

  (Color, String) get _statusView => switch (offer.displayStatus) {
        'ACTIVE' => (AppTheme.verifiedGreen, 'Active'),
        'SCHEDULED' => (const Color(0xFF1A73E8), 'Scheduled'),
        'DRAFT' => (AppTheme.suspendedGrey, 'Draft'),
        _ => (AppTheme.rejectedRed, 'Expired'),
      };

  @override
  Widget build(BuildContext context) {
    final (color, label) = _statusView;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        offer.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(
            '${offer.offerTypeLabel} · ${offer.discountLabel} · ${offer.productCount} product(s)',
            style: const TextStyle(fontSize: 12),
          ),
          if (offer.windowLabel.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(offer.windowLabel, style: const TextStyle(fontSize: 11)),
          ],
        ],
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color),
        ),
      ),
      onTap: () => context.push(Routes.offerDetails, extra: offer),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.onRetry});

  final IconData icon;
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                  onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}

/// Active Offers — every offer running now, scheduled, or a draft.
class ActiveOffersScreen extends StatelessWidget {
  const ActiveOffersScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const OfferBucketScreen(expiredOnly: false);
}

/// Expired Offers — offers whose window already closed.
class ExpiredOffersScreen extends StatelessWidget {
  const ExpiredOffersScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const OfferBucketScreen(expiredOnly: true);
}
