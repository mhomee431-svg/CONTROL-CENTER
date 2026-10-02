import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/pos_models.dart';
import '../controllers/pos_controller.dart';
import '../widgets/pos_shared.dart';

/// POS Error — one screen that explains a POS failure instead of dead-ending.
///
/// It is reached from a failed action (the message travels in the route
/// `extra`), or from the hub when the connector itself reports `ERROR`. Every
/// path out of it is real: reload the module, open connection setup, read the
/// sync history, or go back to the hub.
class PosErrorScreen extends ConsumerStatefulWidget {
  const PosErrorScreen({super.key, this.message});

  /// Pushed-in failure copy (wins over the module state's own message).
  final String? message;

  @override
  ConsumerState<PosErrorScreen> createState() => _PosErrorScreenState();
}

class _PosErrorScreenState extends ConsumerState<PosErrorScreen> {
  @override
  void initState() {
    super.initState();
    // Make sure the diagnostics reflect the connector as it is NOW.
    Future.microtask(() => ref.read(posControllerProvider.notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    final hub = ref.watch(posControllerProvider);
    final integration = hub.integration;
    final hasConnectorProblem = integration != null && integration.hasError;
    final headline =
        widget.message ??
        hub.message ??
        (hasConnectorProblem
            ? 'The connector reported an error'
            : 'Something went wrong with the POS integration');

    return Scaffold(
      appBar: AppBar(title: Text(appText(context).commonPOSProblem)),
      body: SafeArea(
        child: hub.status == PosStatus.loading
            ? const Center(child: CircularProgressIndicator())
            : _ErrorBody(
                headline: headline,
                detail: _detailFor(hub, integration),
                hasIntegration: integration != null,
                connector: integration,
              ),
      ),
    );
  }

  String _detailFor(PosState hub, PosIntegration? integration) {
    if (integration == null) {
      return 'This shop has no POS connector yet. Set one up to sync products '
          'from your billing counter.';
    }
    if (integration.hasError) {
      return [
        'The connector is in an error state'
        '${integration.consecutiveFailures > 0
            ? ' after ${integration.consecutiveFailures} failed attempts'
            : ''}.',
        integration.lastSyncStatus == null
            ? null
            : 'Last sync attempt: ${integration.lastSyncStatus!.toLowerCase()}.',
      ].whereType<String>().join(' ');
    }
    if (hub.status == PosStatus.noShop) {
      return 'Choose a shop first — a POS connector belongs to one shop.';
    }
    return 'The action could not be completed. Nothing was synced.';
  }
}

/// Diagnostics + every way out.
class _ErrorBody extends ConsumerWidget {
  const _ErrorBody({
    required this.headline,
    required this.detail,
    required this.hasIntegration,
    required this.connector,
  });

  final String headline;
  final String detail;
  final bool hasIntegration;
  final PosIntegration? connector;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final status = connector?.status;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Column(
              children: [
                const Icon(
                  Icons.cloud_off_outlined,
                  size: 56,
                  color: AppTheme.rejectedRed,
                ),
                const SizedBox(height: 16),
                Text(
                  headline,
                  key: const Key('pos-error-message'),
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  detail,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: scheme.outline),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (connector != null && status != null) ...[
            Text(appText(context).commonConnector, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      posStatusIcon(status),
                      size: 18,
                      color: posStatusColor(status, scheme),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${connector!.providerName} · '
                        '${posStatusLabel(status)}'
                        '${connector!.lastSyncAt == null
                            ? ''
                            : ' · last sync ${posDateTime(connector!.lastSyncAt!)}'}',
                        style: TextStyle(fontSize: 12, color: scheme.outline),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
          Text(appText(context).commonWhatYouCanDo, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  key: const Key('pos-error-retry'),
                  leading: const Icon(Icons.refresh_outlined),
                  title: Text(appText(context).posErrorScreenCheckTheConnectionAgain),
                  subtitle: Text(
                    appText(context).posErrorScreenReReadTheConnectorAnd,
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => ref.read(posControllerProvider.notifier).load(),
                ),
                const Divider(height: 1),
                ListTile(
                  key: const Key('pos-error-setup'),
                  leading: const Icon(Icons.link_outlined),
                  title: Text(
                    hasIntegration
                        ? 'Review the connection setup'
                        : 'Set up a connector',
                  ),
                  subtitle: Text(
                    hasIntegration
                        ? 'Rotate the vendor credentials and reconnect.'
                        : 'Pick a provider and link your billing counter.',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(Routes.posConnectionSetup),
                ),
                const Divider(height: 1),
                ListTile(
                  key: const Key('pos-error-history'),
                  leading: const Icon(Icons.history_outlined),
                  title: Text(appText(context).commonCheckTheSyncHistory),
                  subtitle: Text(
                    appText(context).posErrorScreenSeeWhetherAnEarlierJob,
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(Routes.posSyncHistory),
                ),
                const Divider(height: 1),
                ListTile(
                  key: const Key('pos-error-back'),
                  leading: const Icon(Icons.point_of_sale_outlined),
                  title: Text(appText(context).commonBackToTheIntegration),
                  subtitle: Text(
                    appText(context).posErrorScreenLeaveThisScreenAndReturn,
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => GoRouter.maybeOf(context)?.go(Routes.pos),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
