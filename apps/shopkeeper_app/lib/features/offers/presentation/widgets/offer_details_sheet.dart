import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/offer_models.dart';
import '../controllers/offers_controller.dart';

/// Offer Details — everything the backend returns for one offer, in one sheet.
///
/// Opened by tapping an offer tile. The offer's own fields are read-only (there
/// is no offer-edit endpoint), but the lifecycle IS actionable: the sheet
/// exposes exactly the status moves the backend allows for the offer's stored
/// status through `PATCH /shopkeeper/shops/{shop_id}/offers/{offer_id}/status`.
class OfferDetailsSheet extends ConsumerStatefulWidget {
  const OfferDetailsSheet({super.key, required this.offer});

  final OfferSummary offer;

  @override
  ConsumerState<OfferDetailsSheet> createState() => _OfferDetailsSheetState();
}

class _OfferDetailsSheetState extends ConsumerState<OfferDetailsSheet> {
  /// True while a status change is in flight (blocks double submission).
  bool _working = false;

  OfferSummary get offer => widget.offer;

  String get _statusLabel {
    if (offer.isLive) return 'Live';
    if (offer.isScheduled) return 'Scheduled';
    if (offer.isDraft) return 'Draft';
    if (offer.isDisabled) return 'Disabled';
    return 'Expired';
  }

  Color _statusColor(ColorScheme scheme) {
    if (offer.isLive) return AppTheme.verifiedGreen;
    if (offer.isDisabled) return AppTheme.suspendedGrey;
    if (offer.isScheduled || offer.isDraft) return AppTheme.pendingAmber;
    return scheme.outline;
  }

  /// Applies one lifecycle move, then closes the sheet.
  ///
  /// [OffersListController.setStatus] reloads the list on success, so the tab
  /// the shopkeeper returns to already shows the offer in its new bucket.
  Future<void> _changeStatus(String status, String doneMessage) async {
    if (_working) return;
    setState(() => _working = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final ok = await ref
        .read(offersListControllerProvider.notifier)
        .setStatus(offer.id, status);
    if (!mounted) return;
    if (ok) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(doneMessage)));
      return;
    }
    // Failure: stay open and show the server's own message.
    setState(() => _working = false);
    messenger.showSnackBar(SnackBar(
      content: Text(ref.read(offersListControllerProvider).message ??
          'Could not update the offer. Please retry.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final window = offer.windowLabel;
    final description = offer.description?.trim() ?? '';
    final terms = offer.termsConditions?.trim() ?? '';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    offer.title,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                ),
              ],
            ),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(scheme).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _statusLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _statusColor(scheme),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  offer.discountLabel,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _DetailRow(
              label: 'Type',
              value: offer.offerTypeLabel,
            ),
            if (window.isNotEmpty)
              _DetailRow(label: 'Validity', value: window),
            _DetailRow(
              label: 'Linked products',
              value: offer.productCount == 1
                  ? '1 product'
                  : '${offer.productCount} products',
            ),
            _DetailRow(
              label: 'Visibility',
              value: offer.isVisible
                  ? 'Visible to customers'
                  : 'Hidden from customers',
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Description', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(description, style: theme.textTheme.bodyMedium),
            ],
            if (terms.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Terms & conditions', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(terms, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 20),
            _StatusActions(
              offer: offer,
              working: _working,
              onActivate: () => _changeStatus('ACTIVE', 'Offer activated'),
              onDisable: () => _changeStatus('DISABLED', 'Offer disabled'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lifecycle actions that are legal for the offer's STORED status.
///
/// The backend owns the transition table (`_OFFER_STATUS_TRANSITIONS`) and
/// re-validates every move — these buttons only mirror it so the shopkeeper is
/// never offered a move the server would reject. A draft can both be activated
/// and disabled, a live offer can only be disabled, and an expired/cancelled
/// offer is terminal, so the sheet explains that instead of showing dead
/// buttons.
class _StatusActions extends StatelessWidget {
  const _StatusActions({
    required this.offer,
    required this.working,
    required this.onActivate,
    required this.onDisable,
  });

  final OfferSummary offer;
  final bool working;
  final VoidCallback onActivate;
  final VoidCallback onDisable;

  Widget _spinner() => const SizedBox(
        height: 18,
        width: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canActivate = offer.canActivate;
    final canDisable = offer.canDisable;

    if (!canActivate && !canDisable) {
      return Text(
        offer.isExpired
            ? 'This offer has ended and can no longer be changed.'
            : 'No lifecycle change is available for this offer.',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.outline),
        textAlign: TextAlign.center,
      );
    }

    return Row(
      children: [
        if (canDisable)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: working ? null : onDisable,
              icon: working
                  ? _spinner()
                  : const Icon(Icons.visibility_off_outlined),
              label: const Text('Disable offer'),
            ),
          ),
        if (canDisable && canActivate) const SizedBox(width: 12),
        if (canActivate)
          Expanded(
            child: FilledButton.icon(
              onPressed: working ? null : onActivate,
              icon: working
                  ? _spinner()
                  : const Icon(Icons.play_circle_outline),
              label: const Text('Activate offer'),
            ),
          ),
      ],
    );
  }
}

/// One label/value line of the details sheet.
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: theme.colorScheme.outline),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// Opens [OfferDetailsSheet] above [context] (the offer tile's tap action).
Future<void> showOfferDetailsSheet(
  BuildContext context,
  OfferSummary offer,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => OfferDetailsSheet(offer: offer),
  );
}
