import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Inline disclosure shown above content that came from the local cache rather
/// than the network.
///
/// ── The rule this enforces ─────────────────────────────────────────────────
/// Cached content is *allowed* — showing a saved product page with no network
/// is far better than an error screen. What is not allowed is letting it pass
/// as live. A customer who reads "₹120" and "In stock" has no way to know
/// those numbers are an hour old, so the app must say so rather than rely on
/// them noticing.
///
/// That is also why this is a warning surface rather than a subtle grey line,
/// and why it always offers a way forward: a notice that just says "this is
/// old" traps the customer with no route to current data.
class StaleDataNotice extends StatelessWidget {
  /// Pre-formatted age line, normally `Last updated …`.
  ///
  /// Kept as a ready-made string rather than a timestamp so the widget cannot
  /// accidentally reword it — the exact phrasing is a product decision, and
  /// the copy is asserted in tests.
  final String? label;

  /// Re-fetches live data. `null` hides the action.
  final VoidCallback? onRetry;

  const StaleDataNotice({super.key, this.label, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      key: const Key('staleDataNotice'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        0,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.history_toggle_off,
            size: 18,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  // Fall back to a generic line rather than rendering null:
                  // an empty row would look like a layout bug and would fail
                  // to disclose anything at all.
                  label ?? 'Showing saved data',
                  key: const Key('staleDataNoticeLabel'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
                Text(
                  'Prices and availability may have changed.',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
          if (onRetry != null)
            TextButton(
              key: const Key('staleDataNoticeRetry'),
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.onSecondaryContainer,
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}
