import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/connectivity_controller.dart';
import '../theme/app_colors.dart';

/// App-wide connectivity bar, rendered by the navigation shell above every
/// screen.
///
///  * online  → renders nothing (zero layout cost);
///  * offline → explains that browsing continues where data is cached and that
///    changes cannot be saved until the connection returns, with a Retry that
///    re-probes the backend;
///  * reconnecting → shows the probe in flight.
///
/// It is deliberately NON-blocking: the app stays browsable and every screen's
/// own error/retry states keep working underneath it.
class ConnectivityBanner extends ConsumerWidget {
  const ConnectivityBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(connectivityControllerProvider);
    return switch (state.status) {
      ConnectivityStatus.online => const SizedBox.shrink(),
      ConnectivityStatus.offline => _bar(
          context,
          bannerKey: const Key('connectivity-banner-offline'),
          icon: Icons.cloud_off_outlined,
          color: AppColors.warning,
          message: "You're offline — changes can't be saved until you're back "
              'online.',
          action: TextButton(
            key: const Key('connectivity-banner-retry'),
            onPressed: () =>
                ref.read(connectivityControllerProvider.notifier).retryNow(),
            child: const Text('Retry'),
          ),
        ),
      ConnectivityStatus.reconnecting => _bar(
          context,
          bannerKey: const Key('connectivity-banner-reconnecting'),
          icon: Icons.sync_outlined,
          color: AppColors.info,
          message: 'Reconnecting…',
          action: const SizedBox(
            key: Key('connectivity-banner-probing'),
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
    };
  }

  Widget _bar(
    BuildContext context, {
    required Key bannerKey,
    required IconData icon,
    required Color color,
    required String message,
    required Widget action,
  }) =>
      Material(
        key: bannerKey,
        color: color.withValues(alpha: 0.12),
        child: SafeArea(
          top: false,
          bottom: false,
          child: Row(
            children: [
              const SizedBox(width: 16),
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    message,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              action,
              const SizedBox(width: 8),
            ],
          ),
        ),
      );
}
