import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/models/search_models.dart';

/// A short, non-promissory inventory-freshness disclaimer.
///
/// Required by the discovery contract: a stock reading is a snapshot of what
/// the shop last reported, not a reservation. The copy deliberately never
/// claims the item *will* be there — only what is currently known.
///
/// Rendered beneath any list of shop-level availability so the customer
/// understands the figure can change before they arrive.
class FreshnessDisclaimer extends StatelessWidget {
  final String? message;

  /// Defaults to [kFreshnessDisclaimer] so every surface stays consistent.
  const FreshnessDisclaimer({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.textMuted.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message ?? kFreshnessDisclaimer,
              style: const TextStyle(
                fontSize: 11,
                height: 1.35,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
