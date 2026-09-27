import 'package:flutter/material.dart';

import '../../core/network/connectivity_service.dart';

/// Slim banner shown above the shell content whenever connectivity is not
/// confirmed.
///
/// Renders nothing while [ConnectivityStatus.online] and while
/// [ConnectivityStatus.unknown], so it can always stay mounted without costing
/// layout.
///
/// ── Why every non-online state is shown ────────────────────────────────────
/// A banner that appears only on a hard disconnect hides the awkward middle:
/// the transport is back but nothing has actually loaded yet. During that
/// window the customer is still seeing errors, so [ConnectivityStatus
/// .reconnecting] gets its own honest "Reconnecting…" line rather than being
/// rounded to "online" and leaving them with no explanation.
class OfflineBanner extends StatelessWidget {
  /// Current connection state.
  final ConnectivityStatus status;

  /// Re-checks connectivity when tapped. `null` hides the action, which is the
  /// right choice in tests and on platforms without the plugin.
  final VoidCallback? onRetry;

  /// Defaults to [ConnectivityStatus.unknown] so a caller that forgets to pass
  /// a status gets the neutral "nothing known yet" rendering rather than
  /// silently alarming the customer with an offline banner that may be untrue.
  const OfflineBanner({
    super.key,
    this.status = ConnectivityStatus.unknown,
    this.onRetry,
  });

  /// Convenience for the common "just a bool" call site.
  const OfflineBanner.connected({super.key})
    : status = ConnectivityStatus.online,
      onRetry = null;

  @override
  Widget build(BuildContext context) {
    // `unknown` is the pre-first-probe state. It renders nothing, which is the
    // whole point of having it: the app shows no banner at launch rather than
    // flashing either a green "all good" (a lie) or a red "you're offline"
    // (also a lie) before it knows anything.
    if (status == ConnectivityStatus.online ||
        status == ConnectivityStatus.unknown) {
      return const SizedBox.shrink();
    }

    final isReconnecting = status == ConnectivityStatus.reconnecting;
    final colors = Theme.of(context).colorScheme;

    // Reconnecting is progress, not failure: a neutral surface avoids the
    // alarming error-red that would make a recovering network look like a
    // broken app.
    final background = isReconnecting ? colors.secondaryContainer : colors.errorContainer;
    final foreground = isReconnecting
        ? colors.onSecondaryContainer
        : colors.onErrorContainer;

    return Material(
      color: background,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              if (isReconnecting)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: foreground,
                  ),
                )
              else
                Icon(Icons.wifi_off, size: 16, color: foreground),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isReconnecting
                      ? 'Reconnecting…'
                      : "You're offline — some content may be unavailable",
                  key: const Key('offlineBannerMessage'),
                  style: TextStyle(
                    fontSize: 13,
                    color: foreground,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (onRetry != null)
                TextButton(
                  key: const Key('offlineBannerRetry'),
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    foregroundColor: foreground,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('Retry'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
