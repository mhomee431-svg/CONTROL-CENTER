import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/state/system_state.dart';
import '../../../../core/state/system_state_view.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/capability_gate.dart';
import '../../../../core/utils/datetime_utils.dart';
import '../../../shell/capabilities_controller.dart';
import '../../domain/pos_models.dart';
import '../controllers/pos_controller.dart';
import '../widgets/pos_shared.dart';
import 'pos_hub_sheets.dart';

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
        title: Text(appText(context).commonDisconnectPOS),
        content: Text(
            appText(context).posScreenScheduledSyncsWillStopYou),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(appText(context).commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(appText(context).commonDisconnect),
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
    final caps = ref.watch(capabilitiesControllerProvider);

    return Scaffold(
      appBar: AppBar(title: Text(appText(context).commonPOSIntegration)),
      // Capability-gated (spec §103): the backend `canUsePos` flag decides
      // whether the POS surface renders at all. The flag is read from the
      // ONE centralized layer — no plan logic here. Backend stays
      // authoritative (state-changing routes still 403 on violation).
      body: CapabilityGate(
        allowed: caps.canUsePos,
        title: appText(context).posScreenPOSNotAvailableOnYour,
        message:
            appText(context).posScreenUpgradeYourPlanToConnect,
        child: SafeArea(
          child: switch (state.status) {
          PosStatus.loading =>
            const Center(child: CircularProgressIndicator()),
          // Both non-ready states render through the ONE shared state view, so
          // "no shop" and "could not load" read exactly like every other empty
          // / failed screen in the app (icon, copy, Retry button).
          PosStatus.noShop => SystemStateView.empty(
              title: appText(context).commonNoShopSelected4,
              message: appText(context).posScreenChooseAShopToManage,
              icon: Icons.storefront_outlined,
            ),
          PosStatus.error => SystemStateView(
              spec: SystemStateSpec.resolve(
                text: appText(context),
                title: state.message ?? 'Could not load POS.',
                message: appText(context).posScreenCheckYourConnectionAndTry,
              ),
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
          appText(context).posScreenConnectYourBillingCounter,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          appText(context).posScreenLinkYourPOSToKeep,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: scheme.outline),
        ),
        const SizedBox(height: 24),
        if (providers.isEmpty)
          Text(
            appText(context).posScreenPOSIntegrationIsNotConfigured,
            key: const Key('pos-not-configured'),
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.outline),
          )
        else ...[
          DropdownButtonFormField<String>(
            initialValue: effective,
            decoration: InputDecoration(labelText: appText(context).commonPOSProvider2),
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
            label: Text(appText(context).commonConnectPOS),
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
    // Error outranks syncing: a failed connector must never read as "Syncing".
    if (integration.hasError) return 'Error';
    if (integration.isSyncing) return 'Syncing';
    if (integration.isConnected) return 'Connected';
    return 'Not Connected';
  }

  IconData get _statusIcon {
    if (integration.hasError) return Icons.error_outline;
    if (integration.isSyncing) return Icons.sync;
    if (integration.isConnected) return Icons.check_circle;
    return Icons.cloud_off;
  }

  Color _statusColor(ColorScheme scheme) {
    if (integration.hasError) return scheme.error;
    if (integration.isSyncing) return AppTheme.pendingAmber;
    if (integration.isConnected) return AppTheme.verifiedGreen;
    return scheme.outline;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                        // Unified freshness voice: "Last POS sync 5 min ago" /
                        // "… today" / "… yesterday", same as Inventory/Price.
                        DateTimeUtils.formatPosSyncFreshness(
                          integration.lastSyncAt,
                        ),
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
                          label: Text(appText(context).commonDisconnect),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: onSync,
                          icon: const Icon(Icons.sync),
                          label: Text(appText(context).commonSyncNow2),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _section(context, 'Manage', _manageTiles(context, integration)),
          const SizedBox(height: 16),
          Text(appText(context).commonSyncHistory, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: jobs.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        appText(context).posScreenNoSyncsYetTapSync,
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
      ),
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

  /// The module's own destinations. "Sync now" above is the one-tap full sync;
  /// the Sync tile opens the screen where the scope is chosen.
  static List<PosHubTile> _manageTiles(
    BuildContext context,
    PosIntegration integration,
  ) =>
      [
    PosHubTile(
      const Key('pos-tile-sync'),
      Icons.sync_outlined,
      'Sync',
      'Choose a full or incremental sync and run it',
      Routes.posSync,
    ),
    PosHubTile(
      const Key('pos-tile-history'),
      Icons.history_outlined,
      'Sync history',
      'Every job the connector has run, with its outcome',
      Routes.posSyncHistory,
    ),
    PosHubTile(
      const Key('pos-tile-setup'),
      Icons.settings_outlined,
      'Connection setup',
      'Vendor, connection type and credentials',
      Routes.posConnectionSetup,
    ),
    PosHubTile(
      const Key('pos-tile-terminals'),
      Icons.point_of_sale_outlined,
      'Terminals',
      integration.deviceCount == 0
          ? 'Map a till or scanner to this connector'
          : '${integration.deviceCount} mapped — view or add another',
      '',
      onTap: () => showPosTerminalsSheet(context),
    ),
    PosHubTile(
      const Key('pos-tile-settings'),
      Icons.tune_outlined,
      'Sync settings',
      'Background sync cadence, pause/resume and who wins a conflict',
      '',
      onTap: () => showPosSyncSettingsSheet(context),
    ),
    PosHubTile(
      const Key('pos-tile-error'),
      Icons.bug_report_outlined,
      'Diagnose a problem',
      integration.hasError
          ? 'The connector is in an error state — see what to do'
          : 'What to check when a sync or the link misbehaves',
      Routes.posError,
    ),
  ];

  Widget _section(BuildContext context, String title, List<PosHubTile> tiles) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                ListTile(
                  key: tiles[i].tileKey,
                  leading: Icon(
                    tiles[i].icon,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(tiles[i].title),
                  subtitle: Text(
                    tiles[i].subtitle,
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  // Sheet-backed tiles (Terminals, Sync settings) open a
                  // dialog; every other tile is a routed destination.
                  onTap: tiles[i].onTap ?? () => context.push(tiles[i].route),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
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

/// Centred icon + copy for the no-shop and error states — rendered by the
/// shared `SystemStateView`, which owns the layout for every feature.

