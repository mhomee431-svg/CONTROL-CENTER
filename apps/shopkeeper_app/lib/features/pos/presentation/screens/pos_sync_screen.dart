import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/ui/primary_cta_bar.dart';
import '../../domain/pos_models.dart';
import '../controllers/pos_controller.dart';
import '../widgets/pos_shared.dart';

/// POS Sync — queue a manual sync for the shop's connector.
///
/// The shopkeeper picks the scope (full or incremental — real server
/// vocabulary), sees what the server knows about the connector, and starts the
/// job. The job itself is followed on the Sync Progress screen; nothing is
/// counted locally.
class PosSyncScreen extends ConsumerStatefulWidget {
  const PosSyncScreen({super.key});

  @override
  ConsumerState<PosSyncScreen> createState() => _PosSyncScreenState();
}

class _PosSyncScreenState extends ConsumerState<PosSyncScreen> {
  @override
  void initState() {
    super.initState();
    // A leftover flow from a previous run must never leak into a new sync.
    Future.microtask(() {
      ref.read(posControllerProvider.notifier).load();
      ref.read(posSyncFlowProvider.notifier).reset();
    });
  }

  Future<void> _start() async {
    final ok = await ref.read(posSyncFlowProvider.notifier).start();
    if (!mounted || !ok) return; // a failure renders inline from the flow state
    context.push(Routes.posSyncProgress);
  }

  @override
  Widget build(BuildContext context) {
    final hub = ref.watch(posControllerProvider);
    final flow = ref.watch(posSyncFlowProvider);
    final integration = hub.integration;

    return Scaffold(
      appBar: AppBar(title: Text(appText(context).commonPOSSync4)),
      body: SafeArea(
        child: PosAsyncBody(
          status: hub.status,
          message: hub.message,
          onRetry: () => ref.read(posControllerProvider.notifier).load(),
          builder: (context) {
            if (integration == null) {
              return PosMessageView(
                icon: Icons.point_of_sale_outlined,
                title: appText(context).commonNoConnectorYet3,
                body: appText(context).posSyncScreenConnectAPOSFirstThere,
                action: FilledButton.icon(
                  key: const Key('pos-sync-go-setup'),
                  onPressed: () => context.push(Routes.posConnectionSetup),
                  icon: const Icon(Icons.link),
                  label: Text(appText(context).commonGoToConnectionSetup2),
                ),
              );
            }
            return _SyncForm(integration: integration, flow: flow);
          },
        ),
      ),
      // BOTTOM LAYER: the one primary action, pinned where every screen keeps
      // it. `PrimaryCtaBar` owns the disabled-while-starting rule too.
      //
      // The bar is omitted entirely when there is no connector. The contract
      // says "Primary CTA *where necessary*" — and in that state the body
      // already renders a filled "Go to connection setup". Keeping the bar
      // would put a SECOND filled button on screen with a primary that cannot
      // ever fire (there is nothing to sync), i.e. exactly the competing-CTA
      // shape: two primaries, one of them a lie.
      bottomNavigationBar: integration == null
          ? null
          : PrimaryCtaBar(
              primaryKey: const Key('pos-sync-start'),
              primaryLabel: appText(context).commonStartSync,
              primaryIcon: Icons.sync,
              onPrimary: _start,
              loading: flow.phase == PosSyncPhase.starting,
            ),
    );
  }
}

/// Scope choice + the connector facts the sync will run against.
class _SyncForm extends ConsumerWidget {
  const _SyncForm({required this.integration, required this.flow});

  final PosIntegration integration;
  final PosSyncFlowState flow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    posStatusIcon(integration.status),
                    color: posStatusColor(integration.status, scheme),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          integration.providerName,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          [
                            '${integration.mappedProducts} products mapped',
                            if (integration.lastSyncAt != null)
                              'Last sync ${posDateTime(integration.lastSyncAt!)}',
                          ].join('  ·  '),
                          style: TextStyle(fontSize: 12, color: scheme.outline),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            appText(context).commonWhatShouldBePulled,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: RadioGroup<String>(
              groupValue: flow.syncType,
              onChanged: (v) {
                if (v != null) {
                  ref.read(posSyncFlowProvider.notifier).selectType(v);
                }
              },
              child: Column(
                children: [
                  RadioListTile<String>(
                    key: const Key('pos-sync-type-full'),
                    value: 'FULL',
                    title: Text(appText(context).commonFullSync),
                    subtitle: Text(
                      appText(context).posSyncScreenReReadTheWholePOS,
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  const Divider(height: 1),
                  RadioListTile<String>(
                    key: const Key('pos-sync-type-incremental'),
                    value: 'INCREMENTAL',
                    title: Text(appText(context).commonIncremental),
                    subtitle: Text(
                      appText(context).posSyncScreenOnlyWhatChangedSinceThe,
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (flow.phase == PosSyncPhase.error) ...[
            const SizedBox(height: 16),
            Card(
              key: const Key('pos-sync-error'),
              margin: EdgeInsets.zero,
              color: scheme.error.withValues(alpha: 0.06),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, size: 20, color: scheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        flow.message ?? 'Could not start the sync.',
                        style: TextStyle(fontSize: 12, color: scheme.error),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
