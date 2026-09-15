import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../domain/offer_models.dart';
import '../controllers/offers_controller.dart';
import '../widgets/offer_create_sheet.dart';

/// Offers management — active, expired, and create new offers.
class OffersScreen extends ConsumerStatefulWidget {
  const OffersScreen({super.key});

  @override
  ConsumerState<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends ConsumerState<OffersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    Future.microtask(
        () => ref.read(offersListControllerProvider.notifier).load());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Opens the create sheet, then refreshes ONLY when an offer was actually
  /// created — otherwise closing the sheet costs no network round-trip.
  Future<void> _openCreateSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const OfferCreateSheet(),
    );
    final created =
        ref.read(offersControllerProvider).status == OfferAssignStatus.done;
    ref.read(offersControllerProvider.notifier).reset();
    if (created) {
      await ref.read(offersListControllerProvider.notifier).load();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Reload when the shopkeeper switches businesses.
    ref.listen(selectedShopProvider, (prev, next) {
      if (prev?.id != next?.id) {
        ref.read(offersListControllerProvider.notifier).load();
      }
    });

    final state = ref.watch(offersListControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Offers & pricing'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Active'),
            Tab(text: 'Expired'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Create offer',
            onPressed: _openCreateSheet,
          ),
        ],
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: [
            _OffersTab(
              offers: state.openOffers,
              state: state,
              showCreateCta: true,
              onCreate: _openCreateSheet,
            ),
            _OffersTab(
              offers: state.expiredOffers,
              state: state,
              showCreateCta: false,
              onCreate: _openCreateSheet,
            ),
          ],
        ),
      ),
    );
  }
}

/// One tab of the offers screen. Both tabs read from the SAME
/// [OffersListState] (one fetch), so they can never disagree.
class _OffersTab extends ConsumerWidget {
  const _OffersTab({
    required this.offers,
    required this.state,
    required this.showCreateCta,
    required this.onCreate,
  });

  final List<OfferSummary> offers;
  final OffersListState state;
  final bool showCreateCta;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return switch (state.status) {
      OffersListStatus.loading =>
        const Center(child: CircularProgressIndicator()),
      OffersListStatus.noShop => _MessageView(
          icon: Icons.storefront_outlined,
          title: 'No shop selected',
          body: 'Choose a shop to see its offers.',
          color: scheme.outline,
        ),
      OffersListStatus.error => _MessageView(
          icon: Icons.cloud_off_outlined,
          title: state.message ?? 'Could not load offers.',
          body: 'Check your connection and try again.',
          color: scheme.outline,
          onRetry: () => ref.read(offersListControllerProvider.notifier).load(),
        ),
      OffersListStatus.ready => offers.isEmpty
          ? _MessageView(
              icon: showCreateCta
                  ? Icons.local_offer_outlined
                  : Icons.history_outlined,
              title: showCreateCta ? 'No active offers' : 'No expired offers',
              body: showCreateCta
                  ? 'Create an offer to attract more customers'
                  : 'Expired offers will appear here',
              color: scheme.outline,
              onCreate: showCreateCta ? onCreate : null,
            )
          : RefreshIndicator(
              onRefresh: () =>
                  ref.read(offersListControllerProvider.notifier).load(),
              child: ListView.separated(
                itemCount: offers.length,
                separatorBuilder: (_, _) => Divider(
                    height: 1, color: Theme.of(context).dividerColor),
                itemBuilder: (context, index) =>
                    _OfferTile(offer: offers[index]),
              ),
            ),
    };
  }
}

class _OfferTile extends StatelessWidget {
  const _OfferTile({required this.offer});

  final OfferSummary offer;

  String get _statusLabel {
    if (offer.isLive) return 'Live';
    if (offer.isScheduled) return 'Scheduled';
    if (offer.isDraft) return 'Draft';
    return 'Expired';
  }

  Color _statusColor(ColorScheme scheme) {
    if (offer.isLive) return AppTheme.verifiedGreen;
    if (offer.isScheduled) return AppTheme.pendingAmber;
    return scheme.outline;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final window = offer.windowLabel;

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: CircleAvatar(
        backgroundColor: scheme.primaryContainer,
        child: Icon(
          offer.isLive
              ? Icons.local_offer
              : offer.isScheduled
                  ? Icons.schedule
                  : Icons.history,
          size: 20,
          color: scheme.primary,
        ),
      ),
      title: Text(
        offer.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(
            [
              offer.discountLabel,
              if (window.isNotEmpty) window,
            ].join('  ·  '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: scheme.onSurface),
          ),
          const SizedBox(height: 2),
          Text(
            offer.productCount == 1
                ? '1 product'
                : '${offer.productCount} products',
            style: TextStyle(fontSize: 11, color: scheme.outline),
          ),
        ],
      ),
      trailing: Text(
        _statusLabel,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _statusColor(scheme),
        ),
      ),
    );
  }
}

/// Centred icon + copy, used for the empty, no-shop and error states.
///
/// [onRetry] renders a retry button (error); [onCreate] renders the primary
/// "Create offer" call-to-action (empty active tab). When both are null the
/// view is purely informational.
class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
    this.onRetry,
    this.onCreate,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color color;
  final VoidCallback? onRetry;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: color),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: color),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
            if (onCreate != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: const Text('Create offer'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
