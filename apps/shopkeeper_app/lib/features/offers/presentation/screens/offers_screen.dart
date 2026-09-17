import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/state/system_state.dart';
import '../../../../core/state/system_state_view.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../domain/offer_models.dart';
import '../controllers/offers_controller.dart';
import '../widgets/offer_create_sheet.dart';
import '../widgets/offer_details_sheet.dart';

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
    return switch (state.status) {
      OffersListStatus.loading =>
        const Center(child: CircularProgressIndicator()),
      // No shop / empty list are EMPTY states: the feature owns the wording and
      // the call to action, the shared view owns the layout.
      OffersListStatus.noShop => SystemStateView.empty(
          title: 'No shop selected',
          message: 'Choose a shop to see its offers.',
          icon: Icons.storefront_outlined,
        ),
      OffersListStatus.error => SystemStateView(
          spec: SystemStateSpec.resolve(
            state: SystemState.genericRetry,
            title: state.message ?? 'Could not load offers.',
            message: 'Check your connection and try again.',
          ),
          onRetry: () => ref.read(offersListControllerProvider.notifier).load(),
        ),
      OffersListStatus.ready => offers.isEmpty
          ? SystemStateView.empty(
              title: showCreateCta ? 'No active offers' : 'No expired offers',
              message: showCreateCta
                  ? 'Create an offer to attract more customers'
                  : 'Expired offers will appear here',
              icon: showCreateCta
                  ? Icons.local_offer_outlined
                  : Icons.history_outlined,
              action: showCreateCta
                  ? FilledButton.icon(
                      onPressed: onCreate,
                      icon: const Icon(Icons.add),
                      label: const Text('Create offer'),
                    )
                  : null,
            )
          : RefreshIndicator(
              onRefresh: () =>
                  ref.read(offersListControllerProvider.notifier).load(),
              child: ListView.separated(
                itemCount: offers.length,
                separatorBuilder: (_, _) => Divider(
                    height: 1, color: Theme.of(context).dividerColor),
                itemBuilder: (context, index) => _OfferTile(
                  offer: offers[index],
                  onTap: () =>
                      showOfferDetailsSheet(context, offers[index]),
                ),
              ),
            ),
    };
  }
}

class _OfferTile extends StatelessWidget {
  const _OfferTile({required this.offer, required this.onTap});

  final OfferSummary offer;

  /// Opens the full Offer Details sheet (the row is a summary only).
  final VoidCallback onTap;

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
      onTap: onTap,
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
/// The layout lives in the shared [SystemStateView]; this file only decides
/// which state applies and what its copy/action is.
