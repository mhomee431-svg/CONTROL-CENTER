import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/state/system_state.dart';
import '../../../../core/state/system_state_view.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/filter_ui.dart';
import '../../../../core/ui/lazy_list.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../domain/offer_models.dart';
import '../controllers/offers_controller.dart';
import '../widgets/offer_create_sheet.dart';
import '../widgets/offer_details_sheet.dart';

/// Offers management — filter across active, scheduled, expired and disabled
/// offers, and create new ones.
class OffersScreen extends ConsumerStatefulWidget {
  const OffersScreen({super.key});

  @override
  ConsumerState<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends ConsumerState<OffersScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => ref.read(offersListControllerProvider.notifier).load());
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

    // Each filter owns its empty copy — the layout is shared, the wording
    // answers the question that filter asks.
    final (emptyTitle, emptyMessage, emptyIcon, showCreateCta) =
        switch (state.filter) {
      OfferFilter.active => (
          'No active offers',
          'Create an offer to attract more customers',
          Icons.local_offer_outlined,
          true,
        ),
      OfferFilter.scheduled => (
          'No scheduled offers',
          'Offers waiting for their start time appear here',
          Icons.schedule_outlined,
          false,
        ),
      OfferFilter.expired => (
          'No expired offers',
          'Expired offers will appear here',
          Icons.history_outlined,
          false,
        ),
      OfferFilter.disabled => (
          'No disabled offers',
          'Offers you disable appear here and can be re-activated',
          Icons.visibility_off_outlined,
          false,
        ),
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Offers & pricing'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Create offer',
            onPressed: _openCreateSheet,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // The filter — single-select chips from the shared filter UI,
            // the same interaction model as the products / inventory screens.
            // State lives in the controller (not in a TabController), so it
            // survives rebuilds and reloads.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: FilterChipBar<OfferFilter>(
                options: const [
                  FilterChoice(value: OfferFilter.active, label: 'Active'),
                  FilterChoice(
                    value: OfferFilter.scheduled,
                    label: 'Scheduled',
                  ),
                  FilterChoice(value: OfferFilter.expired, label: 'Expired'),
                  FilterChoice(value: OfferFilter.disabled, label: 'Disabled'),
                ],
                selected: state.filter,
                onSelected: (value) => ref
                    .read(offersListControllerProvider.notifier)
                    .setFilter(value),
              ),
            ),
            Expanded(
              child: _OffersTab(
                offers: state.visibleOffers,
                state: state,
                emptyTitle: emptyTitle,
                emptyMessage: emptyMessage,
                emptyIcon: emptyIcon,
                showCreateCta: showCreateCta,
                onCreate: _openCreateSheet,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The offers screen's list body — one instance per screen; the filter chips
/// swap WHICH slice it renders. It always reads the SAME [OffersListState]
/// (one fetch), so no two views of the list can ever disagree.
class _OffersTab extends ConsumerWidget {
  const _OffersTab({
    required this.offers,
    required this.state,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.emptyIcon,
    required this.onCreate,
    this.showCreateCta = false,
  });

  final List<OfferSummary> offers;
  final OffersListState state;

  /// Empty-list copy — each filter owns its own wording.
  final String emptyTitle;
  final String emptyMessage;
  final IconData emptyIcon;
  final VoidCallback onCreate;

  /// When true the empty state also shows the "Create offer" call to action.
  final bool showCreateCta;

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
      // ONE pull-to-refresh-able list for the rows and the empty state:
      // AlwaysScrollable physics keeps the pull gesture alive even when this
      // bucket has nothing to scroll (a fresh offer created elsewhere still
      // arrives), and the empty copy keeps the filter's own wording.
      OffersListStatus.ready => RefreshIndicator(
          onRefresh: () =>
              ref.read(offersListControllerProvider.notifier).load(),
          child: LazyListView(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: offers.length,
            separatorBuilder: (_, _) => Divider(
                height: 1, color: Theme.of(context).dividerColor),
            itemBuilder: (context, index) => _OfferTile(
              offer: offers[index],
              onTap: () => showOfferDetailsSheet(context, offers[index]),
            ),
            emptyPlaceholder: SystemStateView.empty(
              title: emptyTitle,
              message: emptyMessage,
              icon: emptyIcon,
              action: showCreateCta
                  ? FilledButton.icon(
                      onPressed: onCreate,
                      icon: const Icon(Icons.add),
                      label: const Text('Create offer'),
                    )
                  : null,
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
    if (offer.isDisabled) return 'Disabled';
    return 'Expired';
  }

  Color _statusColor(ColorScheme scheme) {
    if (offer.isLive) return AppTheme.verifiedGreen;
    if (offer.isScheduled) return AppTheme.pendingAmber;
    if (offer.isDisabled) return AppTheme.suspendedGrey;
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
                  : offer.isDisabled
                      ? Icons.visibility_off_outlined
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
