import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../offers/domain/offer_models.dart';
import '../../../offers/presentation/controllers/offers_controller.dart';
import '../../../inventory/presentation/widgets/inventory_shared.dart'
    show InfoChip, shortDateLabel;

/// Offer Details — every server-reported field of one offer: type, discount,
/// validity window, status bucket, linked product count and terms.
///
/// Receives the [OfferSummary] selected in the list as a route `extra`.
/// Activate/disable actions mirror `_OFFER_STATUS_TRANSITIONS`; the backend
/// re-validates every move.
class OfferDetailsScreen extends ConsumerStatefulWidget {
  const OfferDetailsScreen({super.key, required this.offer});

  final OfferSummary offer;

  @override
  ConsumerState<OfferDetailsScreen> createState() =>
      _OfferDetailsScreenState();
}

class _OfferDetailsScreenState extends ConsumerState<OfferDetailsScreen> {
  /// True while a status change is in flight (blocks double submission).
  bool _working = false;

  OfferSummary get offer => widget.offer;

  (Color, String) get _statusView => switch (offer.displayStatus) {
        'ACTIVE' => (AppTheme.verifiedGreen, 'Active'),
        'SCHEDULED' => (AppColors.primary, 'Scheduled'),
        'DRAFT' => (AppTheme.suspendedGrey, 'Draft'),
        'DISABLED' => (AppTheme.suspendedGrey, 'Disabled'),
        _ => (AppTheme.rejectedRed, 'Expired'),
      };

  /// Applies one lifecycle move.
  ///
  /// The list controller reloads on success, so going back to the list shows
  /// the offer in its new bucket.
  Future<void> _changeStatus(String status, String doneMessage) async {
    if (_working) return;
    setState(() => _working = true);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref
        .read(offersListControllerProvider.notifier)
        .setStatus(offer.id, status);
    if (!mounted) return;
    setState(() => _working = false);
    messenger.showSnackBar(SnackBar(
      content: Text(ok
          ? doneMessage
          : ref.read(offersListControllerProvider).message ??
              'Could not update the offer. Please retry.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    final (color, statusLabel) = _statusView;

    final rows = <(String, String)>[
      ('Offer type', offer.offerTypeLabel),
      ('Discount', offer.discountLabel),
      (
        'Start date',
        offer.startDate == null ? '—' : shortDateLabel(offer.startDate!)
      ),
      (
        'End date',
        offer.endDate == null ? '—' : shortDateLabel(offer.endDate!)
      ),
      ('Linked products', '${offer.productCount}'),
      ('Stored status', offer.status),
      (
        'Terms & conditions',
        (offer.termsConditions == null || offer.termsConditions!.isEmpty)
            ? '—'
            : offer.termsConditions!
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Offer details')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          offer.title,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      InfoChip(label: statusLabel, color: color),
                    ],
                  ),
                  if (offer.description != null &&
                      offer.description!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      offer.description!,
                      style: TextStyle(fontSize: 13, color: outline),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    offer.windowLabel,
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, color: Theme.of(context).dividerColor),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 130,
                          child: Text(
                            rows[i].$1,
                            style: TextStyle(
                              fontSize: 13,
                              color: outline,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            rows[i].$2,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          _StatusActions(
            offer: offer,
            working: _working,
            onActivate: () => _changeStatus('ACTIVE', 'Offer activated'),
            onDisable: () => _changeStatus('DISABLED', 'Offer disabled'),
          ),
        ],
      ),
    );
  }
}

/// Activate/disable buttons for the moves the backend allows.
///
/// Expired and cancelled offers are terminal, so the screen explains that
/// instead of showing buttons the server would reject.
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

  @override
  Widget build(BuildContext context) {
    final canActivate = offer.canActivate;
    final canDisable = offer.canDisable;

    if (!canActivate && !canDisable) {
      return Text(
        offer.isExpired
            ? 'This offer has ended and can no longer be changed.'
            : 'No lifecycle change is available for this offer.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.outline,
        ),
      );
    }

    return Row(
      children: [
        if (canDisable)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: working ? null : onDisable,
              icon: const Icon(Icons.visibility_off_outlined),
              label: const Text('Disable offer'),
            ),
          ),
        if (canDisable && canActivate) const SizedBox(width: 12),
        if (canActivate)
          Expanded(
            child: FilledButton.icon(
              onPressed: working ? null : onActivate,
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('Activate offer'),
            ),
          ),
      ],
    );
  }
}
