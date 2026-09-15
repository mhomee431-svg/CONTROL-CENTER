import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/pos_models.dart';
import '../controllers/pos_controller.dart';

/// POS (Point of Sale) integration — connect a vendor connector, trigger
/// syncs, and watch the real job history. All state comes from
/// [PosController]; nothing is invented client-side.
class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  String? _selectedProvider;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(posControllerProvider.notifier).load());
  }

  Future<void> _connect() async {
    final provider = _selectedProvider ??
        (ref.read(posControllerProvider).providers.isNotEmpty
            ? ref.read(posControllerProvider).providers.first.code
            : null);
    if (provider == null) return;
    final connected =
        await ref.read(posControllerProvider.notifier).connect(provider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          connected
              ? 'POS connected successfully'
              : 'Connection failed — check the credentials and retry',
        ),
      ),
    );
  }

  Future<void> _syncNow() async {
    final job = await ref.read(posControllerProvider.notifier).syncNow();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          job == null
              ? 'Sync could not be started'
              : 'Sync queued — products will update shortly',
        ),
      ),
    );
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect POS?'),
        content: const Text(
            'Scheduled syncs will stop. You can reconnect at any time.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(posControllerProvider.notifier).disconnect();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(posControllerProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('POS integration')),
      body: SafeArea(
        child: switch (state.status) {
          PosStatus.loading =>
            const Center(child: CircularProgressIndicator()),
          PosStatus.noShop => _MessageView(
              icon: Icons.storefront_outlined,
              title: 'No shop selected',
              body: 'Choose a shop to manage its POS integration.',
              color: scheme.outline,
            ),
          PosStatus.error => _MessageView(
              icon: Icons.cloud_off_outlined,
              title: state.message ?? 'Could not load POS.',
              body: 'Check your connection and try again.',
              color: scheme.outline,
              onRetry: () => ref.read(posControllerProvider.notifier).load(),
            ),
          PosStatus.ready when state.needsOnboarding => _ConnectView(
              providers: state.providers,
              selectedProvider: _selectedProvider,
              onSelect: (code) => setState(() => _selectedProvider = code),
              onConnect: _connect,
            ),
          PosStatus.ready => _ConnectedView(
              integration: state.integration!,
              jobs: state.jobs,
              onSync: _syncNow,
              onDisconnect: _disconnect,
            ),
        },
      ),
    );
  }
}


/// First-run view: pick a vendor connector and link it to this shop.
class _ConnectView extends StatelessWidget {
  const _ConnectView({
    required this.providers,
    required this.selectedProvider,
    required this.onSelect,
    required this.onConnect,
  });

  final List<PosProviderInfo> providers;
  final String? selectedProvider;
  final ValueChanged<String> onSelect;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effective =
        selectedProvider ?? (providers.isNotEmpty ? providers.first.code : null);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 24),
        Icon(Icons.point_of_sale_outlined, size: 56, color: scheme.outline),
        const SizedBox(height: 16),
        Text(
          'Connect your billing counter',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Link your POS to keep products and stock in step automatically.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: scheme.outline),
        ),
        const SizedBox(height: 24),
        if (providers.isEmpty)
          Text(
            'No POS connectors are available right now.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.outline),
          )
        else ...[
          DropdownButtonFormField<String>(
            initialValue: effective,
            decoration: const InputDecoration(labelText: 'POS provider'),
            items: [
              for (final p in providers)
                DropdownMenuItem(value: p.code, child: Text(p.displayName)),
            ],
            onChanged: (code) {
              if (code != null) onSelect(code);
            },
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onConnect,
            icon: const Icon(Icons.link),
            label: const Text('Connect POS'),
          ),
        ],
      ],
    );
  }
}

/// Connected / errored / disconnected view: live status card, sync trigger,
/// disconnect, and the real sync-job history.
class _ConnectedView extends StatelessWidget {
  const _ConnectedView({
    required this.integration,
    required this.jobs,
    required this.onSync,
    required this.onDisconnect,
  });

  final PosIntegration integration;
  final List<PosSyncJob> jobs;
  final VoidCallback onSync;
  final VoidCallback onDisconnect;

  String get _statusLabel {
    if (integration.isConnected) return 'Connected';
    if (integration.hasError) return 'Connection error';
    return 'Disconnected';
  }

  IconData get _statusIcon {
    if (integration.isConnected) return Icons.check_circle;
    if (integration.hasError) return Icons.error_outline;
    return Icons.cloud_off;
  }

  Color _statusColor(ColorScheme scheme) {
    if (integration.isConnected) return AppTheme.verifiedGreen;
    if (integration.hasError) return scheme.error;
    return scheme.outline;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_statusIcon, color: _statusColor(scheme)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            integration.providerName,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            _statusLabel,
                            style: TextStyle(
                              fontSize: 12,
                              color: _statusColor(scheme),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  [
                    '${integration.mappedProducts} products mapped',
                    '${integration.deviceCount} devices',
                    if (integration.lastSyncAt != null)
                      'Last sync: ${_ConnectedView.shortDateTime(integration.lastSyncAt!)}',
                  ].join('  ·  '),
                  style: TextStyle(fontSize: 12, color: scheme.outline),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onDisconnect,
                        icon: const Icon(Icons.link_off),
                        label: const Text('Disconnect'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onSync,
                        icon: const Icon(Icons.sync),
                        label: const Text('Sync now'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Sync history', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          child: jobs.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'No syncs yet.\nTap "Sync now" to pull your POS data.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.outline),
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < jobs.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _SyncJobTile(job: jobs[i]),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// Compact `12 Jan 2026, 08:30` formatting (no intl dependency).
  static String shortDateTime(DateTime dt) =>
      '${dt.day} ${_months[dt.month - 1]} ${dt.year}, '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}


class _SyncJobTile extends StatelessWidget {
  const _SyncJobTile({required this.job});

  final PosSyncJob job;

  String get _detail {
    if (job.isFailed) return job.errorSummary ?? 'Sync failed';
    if (job.isQueued || job.isRunning) return 'Sync ${job.status.toLowerCase()}…';
    return '${job.itemsSucceeded} products synced'
        '${job.itemsFailed > 0 ? ', ${job.itemsFailed} failed' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconColor = job.isFailed
        ? scheme.error
        : job.isQueued || job.isRunning
            ? AppTheme.pendingAmber
            : AppTheme.verifiedGreen;
    final icon = job.isFailed
        ? Icons.error_outline
        : job.isQueued || job.isRunning
            ? Icons.schedule
            : Icons.check_circle;
    final time = job.startedAt != null
        ? _ConnectedView.shortDateTime(job.startedAt!)
        : '';

    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20, color: iconColor),
      title: Text(_detail, style: const TextStyle(fontSize: 13)),
      subtitle: Text(
        job.syncType == 'INCREMENTAL' ? 'Incremental' : 'Full sync',
        style: TextStyle(fontSize: 11, color: scheme.outline),
      ),
      trailing: Text(
        time,
        style: TextStyle(fontSize: 11, color: scheme.outline),
      ),
    );
  }
}

/// Centred icon + copy for the no-shop and error states.
class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color color;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: color),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: color),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

