import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/offer_models.dart';

/// Offer Details — everything the backend returns for one offer, in one sheet.
///
/// Opened by tapping an offer tile. Read-only by design: the backend exposes
/// `POST /offers` (create) and `GET /offers` (list) — there is no update or
/// delete endpoint, so the sheet never pretends otherwise.
class OfferDetailsSheet extends StatelessWidget {
  const OfferDetailsSheet({super.key, required this.offer});

  final OfferSummary offer;

  String get _statusLabel {
    if (offer.isLive) return 'Live';
    if (offer.isScheduled) return 'Scheduled';
    if (offer.isDraft) return 'Draft';
    return 'Expired';
  }

  Color _statusColor(ColorScheme scheme) {
    if (offer.isLive) return AppTheme.verifiedGreen;
    if (offer.isScheduled || offer.isDraft) return AppTheme.pendingAmber;
    return scheme.outline;
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
          ],
        ),
      ),
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
