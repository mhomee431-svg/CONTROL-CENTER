import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Marks a list that came from the device's offline snapshot rather than a
/// live backend response.
///
/// Why this must exist: `ProductsSnapshotStore` serves the last synced
/// inventory while the device is offline, which is genuinely useful — but a
/// stale quantity or price that LOOKS live is worse than no data at all, since
/// the shopkeeper could act on a number that has already changed on the server.
/// So a cached payload is always shown WITH its provenance.
///
/// Scope: this notices the DATA, not the network. It renders only when the
/// payload was rebuilt from the snapshot (`fromCache`), never merely because
/// the link is down — the app-wide `ConnectivityBanner` already covers that,
/// and the two must not say the same thing twice.
class CachedDataNotice extends StatelessWidget {
  const CachedDataNotice({super.key, this.message});

  /// Optional feature-specific wording (e.g. "Showing your last synced
  /// prices"). Defaults to the inventory list's own sentence.
  final String? message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('cached-data-notice'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.history_outlined, size: 20, color: scheme.onSurface),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message ??
                  'Showing your last synced list — reconnect to refresh it.',
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
