import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/router/route_names.dart';
import '../../domain/pos_models.dart';
import '../controllers/pos_controller.dart';
import '../widgets/pos_shared.dart';

/// How a vendor connector can talk to the backend (server vocabulary, default
/// `API`).
const List<(String, String)> kPosIntegrationTypes = [
  ('API', 'Direct API connection'),
  ('FILE_UPLOAD', 'File upload'),
  ('WEBHOOK', 'Webhook push'),
];

/// POS Connection Setup — link a vendor connector to this shop.
///
/// * First run: pick the provider from the real registry, choose how it talks to
///   the backend, optionally add vendor credentials, then register + connect.
/// * Existing connector: rotate the credentials and reconnect — the provider is
///   fixed, so a second connector is never created by accident.
///
/// A credential refusal is reported AS a credential refusal (the setup stays
/// open for correction); only a transport failure offers a plain Retry.
class PosConnectionSetupScreen extends ConsumerStatefulWidget {
  const PosConnectionSetupScreen({super.key});

  @override
  ConsumerState<PosConnectionSetupScreen> createState() =>
      _PosConnectionSetupScreenState();
}

class _PosConnectionSetupScreenState
    extends ConsumerState<PosConnectionSetupScreen> {
  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _apiSecretController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(posSetupProvider.notifier).load());
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _apiSecretController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    await ref.read(posSetupProvider.notifier).submit();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(posSetupProvider);
    final scheme = Theme.of(context).colorScheme;
    final finished = state.status == PosSetupStatus.done;

    return Scaffold(
      appBar: AppBar(title: Text(appText(context).commonPOSConnectionSetup)),
      body: SafeArea(
        child: switch (state.status) {
          PosSetupStatus.loading =>
            const Center(child: CircularProgressIndicator()),
          PosSetupStatus.error when state.providers.isEmpty => PosMessageView(
            icon: Icons.cloud_off_outlined,
            title: state.message ?? 'Could not load the POS providers.',
            body: appText(context).posConnectionSetupScreenCheckYourConnectionAndTry,
            onRetry: () => ref.read(posSetupProvider.notifier).load(),
          ),
          PosSetupStatus.done => _SetupSuccessView(integration: state.integration!),
          _ => _SetupForm(
            state: state,
            baseUrl: _baseUrlController,
            apiKey: _apiKeyController,
            apiSecret: _apiSecretController,
          ),
        },
      ),
      // The action is pinned outside the scroll view so it stays reachable no
      // matter how long the credential form grows.
      bottomNavigationBar: finished
          ? null
          : Material(
              elevation: 8,
              color: scheme.surface,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton.icon(
                    key: const Key('pos-setup-submit'),
                    onPressed: state.status == PosSetupStatus.connecting
                        ? null
                        : _submit,
                    icon: state.status == PosSetupStatus.connecting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.link),
                    label: Text(
                      state.existing == null ? 'Connect POS' : 'Save & reconnect',
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}


/// The provider / type / credentials form.
class _SetupForm extends ConsumerWidget {
  const _SetupForm({
    required this.state,
    required this.baseUrl,
    required this.apiKey,
    required this.apiSecret,
  });

  final PosSetupState state;

  /// Owned by the screen state — never rebuilt inside build, so typing keeps
  /// the cursor stable.
  final TextEditingController baseUrl;
  final TextEditingController apiKey;
  final TextEditingController apiSecret;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final existing = state.existing;
    final provider = existing == null
        ? state.providers
              .where((p) => p.code == state.effectiveProvider)
              .firstOrNull
        : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (existing != null)
            _ExistingCard(integration: existing)
          else ...[
            Text(
              appText(context).posConnectionSetupScreenLinkYourPOSToKeep,
              style: TextStyle(fontSize: 13, color: scheme.outline),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: const Key('pos-setup-provider'),
              initialValue: state.effectiveProvider.isEmpty
                  ? null
                  : state.effectiveProvider,
              decoration: InputDecoration(labelText: appText(context).commonPOSProvider),
              items: [
                for (final p in state.providers)
                  DropdownMenuItem(value: p.code, child: Text(p.displayName)),
              ],
              onChanged: (code) {
                if (code != null) {
                  ref.read(posSetupProvider.notifier).selectProvider(code);
                }
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const Key('pos-setup-type'),
              initialValue: state.integrationType,
              decoration: InputDecoration(labelText: appText(context).commonConnectionType),
              items: [
                for (final (value, label) in kPosIntegrationTypes)
                  DropdownMenuItem(value: value, child: Text(label)),
              ],
              onChanged: (type) {
                if (type != null) {
                  ref
                      .read(posSetupProvider.notifier)
                      .selectIntegrationType(type);
                }
              },
            ),
          ],
          if (provider != null && !provider.supportsIncremental) ...[
            const SizedBox(height: 8),
            Text(
              appText(context).posConnectionSetupScreenThisConnectorSupportsFullSyncs,
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
          ],
          const SizedBox(height: 16),
          _CredentialsCard(baseUrl: baseUrl, apiKey: apiKey, apiSecret: apiSecret),
          const SizedBox(height: 16),
          if (state.status == PosSetupStatus.error) ...[
            _SetupErrorCard(state: state),
            const SizedBox(height: 16),
          ],
          Text(
            existing == null
                ? 'Registering creates the link; the vendor is then asked to '
                      'validate it before your products start syncing.'
                : 'Reconnecting re-validates the stored credentials with the '
                      'vendor and switches the connector back on.',
            style: TextStyle(fontSize: 11, color: scheme.outline),
          ),
        ],
      ),
    );
  }
}

/// An already-registered connector, shown when setup is opened in
/// reconnect / credential-rotation mode.
class _ExistingCard extends StatelessWidget {
  const _ExistingCard({required this.integration});

  final PosIntegration integration;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = integration.status;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(posStatusIcon(status), color: posStatusColor(status, scheme)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    integration.providerName,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    appText(context).posConnectionSetupScreenThisShopAlreadyHasA(posStatusLabel(status)),
                    style: TextStyle(fontSize: 12, color: scheme.outline),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Optional vendor credentials (API base URL / key / secret). The controllers
/// are owned by the screen so typing never resets the cursor.
class _CredentialsCard extends ConsumerWidget {
  const _CredentialsCard({
    required this.baseUrl,
    required this.apiKey,
    required this.apiSecret,
  });

  final TextEditingController baseUrl;
  final TextEditingController apiKey;
  final TextEditingController apiSecret;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(appText(context).posConnectionSetupScreenVendorCredentialsOptional),
            const SizedBox(height: 4),
            Text(
              appText(context).posConnectionSetupScreenOnlyWhatYouTypeIs,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('pos-setup-api-base-url'),
              controller: baseUrl,
              onChanged: (v) => ref
                  .read(posSetupProvider.notifier)
                  .editCredentials(apiBaseUrl: v),
              keyboardType: TextInputType.url,
              decoration: InputDecoration(labelText: appText(context).commonAPIBaseURL),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('pos-setup-api-key'),
              controller: apiKey,
              onChanged: (v) =>
                  ref.read(posSetupProvider.notifier).editCredentials(apiKey: v),
              decoration: InputDecoration(labelText: appText(context).commonAPIKey),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('pos-setup-api-secret'),
              controller: apiSecret,
              onChanged: (v) => ref
                  .read(posSetupProvider.notifier)
                  .editCredentials(apiSecret: v),
              obscureText: true,
              decoration: InputDecoration(labelText: appText(context).commonAPISecret),
            ),
          ],
        ),
      ),
    );
  }
}

/// Readable failure panel — a credential refusal is called out as such.
class _SetupErrorCard extends StatelessWidget {
  const _SetupErrorCard({required this.state});

  final PosSetupState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const Key('pos-setup-error'),
      margin: EdgeInsets.zero,
      color: scheme.error.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              state.credentialRefused
                  ? Icons.key_off_outlined
                  : Icons.error_outline,
              size: 20,
              color: scheme.error,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.credentialRefused
                        ? 'The vendor did not accept this link'
                        : 'Could not complete the setup',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.error,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    state.message ?? '',
                    style: TextStyle(fontSize: 12, color: scheme.error),
                  ),
                  if (state.credentialRefused) ...[
                    const SizedBox(height: 4),
                    Text(
                      appText(context).posConnectionSetupScreenCheckTheAPIKeySecret,
                      style: TextStyle(fontSize: 11, color: scheme.outline),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Success panel: the connector is live, and the shopkeeper can start the
/// first product sync from here instead of hunting for it on the POS screen.
class _SetupSuccessView extends ConsumerWidget {
  const _SetupSuccessView({required this.integration});

  final PosIntegration integration;

  /// Queues the initial sync and reports the outcome; the POS screen is where
  /// the queued job and its progress are shown.
  Future<void> _syncNow(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final sync = await ref.read(posControllerProvider.notifier).syncNow();
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          sync == null
              ? 'Sync could not be started — open the POS screen to retry.'
              : 'Initial sync started. Open the POS screen for progress.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final status = integration.status;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.verified_outlined,
              size: 56,
              color: AppTheme.verifiedGreen,
            ),
            const SizedBox(height: 16),
            Text(
              appText(context).commonPOSConnected,
              key: const Key('pos-setup-success'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              appText(context).posConnectionSetupScreenProviderNameIsValue(integration.providerName, posStatusLabel(status).toLowerCase()),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: scheme.outline),
            ),
            const SizedBox(height: 16),
            PosStatusChip(
              key: const Key('pos-setup-status'),
              label: posStatusLabel(status),
              color: posStatusColor(status, scheme),
              icon: posStatusIcon(status),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('pos-setup-sync-now'),
                onPressed: () => _syncNow(context, ref),
                icon: const Icon(Icons.sync_outlined),
                label: Text(appText(context).commonSyncNow),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('pos-setup-done'),
                onPressed: () => GoRouter.maybeOf(context)?.go(Routes.pos),
                icon: const Icon(Icons.point_of_sale_outlined),
                label: Text(appText(context).commonBackToIntegration),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

