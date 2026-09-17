import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../offers/domain/offer_models.dart';
import '../../../inventory/presentation/widgets/inventory_shared.dart'
    show InfoChip, shortDateLabel;

/// Offer Details — every server-reported field of one offer: type, discount,
/// validity window, status bucket, linked product count and terms.
///
/// Receives the [OfferSummary] selected in the list as a route `extra`.
class OfferDetailsScreen extends StatelessWidget {
  const OfferDetailsScreen({super.key, required this.offer});

  final OfferSummary offer;

  (Color, String) get _statusView => switch (offer.displayStatus) {
        'ACTIVE' => (AppTheme.verifiedGreen, 'Active'),
        'SCHEDULED' => (const Color(0xFF1A73E8), 'Scheduled'),
        'DRAFT' => (AppTheme.suspendedGrey, 'Draft'),
        _ => (AppTheme.rejectedRed, 'Expired'),
      };

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
        ],
      ),
    );
  }
}
