import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../pos/presentation/controllers/pos_controller.dart';
import '../../../pos/domain/pos_models.dart';
import '../controllers/import_controller.dart';
import '../../domain/import_models.dart';

/// Import Center — the central hub for bringing inventory into the shop.
///
/// Two primary methods are surfaced as the main entry points:
///   1. Excel / CSV — upload a workbook to bulk-update stock / pricing / catalog.
///   2. POS sync    — pull products + sales from a connected POS vendor.
///
/// Below the methods a compact status summary is shown (last import, last
/// sync, failed counts, quick-history) so the shopkeeper always sees where
/// each channel stands.
class ImportCenterScreen extends ConsumerStatefulWidget {
  const ImportCenterScreen({super.key});

  @override
  ConsumerState<ImportCenterScreen> createState() =>
      _ImportCenterScreenState();
}

class _ImportCenterScreenState extends ConsumerState<ImportCenterScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(importControllerProvider.notifier).loadJobs(),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SampleDownloadState>(sampleDownloadProvider, (prev, next) {
      final message = next.message;
      if (message != null && prev?.message != message) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
        ref.read(sampleDownloadProvider.notifier).clearMessage();
      }
    });

        final jobs = ref.watch(importControllerProvider.select((s) => s.jobs));

    // POS sync status is read live from the POS controller so the summary
    // never shows stale data.
    final posState = ref.watch(posControllerProvider);
    final posIntegration = posState.integration;
    final posJobs = posState.jobs;
    final hasPos = posIntegration != null;
    final posSyncStatus = _lastPosSyncStatus(posIntegration, posJobs);

    final failedImports =
        jobs.where((j) => j.status == 'FAILED').length;

    return Scaffold(
      appBar: AppBar(title: Text(appText(context).commonImportCenter)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            appText(context).importCenterScreenBringProductsIntoYourShop,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 20),
          _MethodCard(
            key: const Key('method-excel-csv'),
            icon: Icons.upload_file_outlined,
            title: appText(context).commonExcelCSV,
            subtitle: appText(context).importCenterScreenBulkUploadAWorkbookTo,
            onTap: () {
              ref.read(importControllerProvider.notifier).resetFlow();
              context.push(Routes.importUpload);
            },
          ),
          const SizedBox(height: 12),
          // Supporting action for the Excel path: the template the shopkeeper
          // fills in before uploading. Keyed for the flow tests.
          _DownloadSampleTile(
            downloading: ref.watch(
              sampleDownloadProvider.select((s) => s.inProgress),
            ),
            onTap: () => ref.read(sampleDownloadProvider.notifier).download(),
          ),
          const SizedBox(height: 12),
          _MethodCard(
            key: const Key('method-pos-sync'),
            icon: Icons.point_of_sale_outlined,
            title: appText(context).commonPOSSync3,
            subtitle: hasPos
                ? 'Connected to ${_integrationName(posIntegration)}. '
                    'Sync products and sales from your POS.'
                : 'Connect a POS system to sync products and sales automatically.',
            onTap: () {
              context.push(Routes.pos);
            },
          ),
          const SizedBox(height: 24),
          Text(
            appText(context).commonActivity,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  key: const Key('summary-last-import'),
                  leading: const CircleAvatar(
                    radius: 16,
                    child: Icon(Icons.upload_file_outlined, size: 18),
                  ),
                  title: Text(appText(context).commonLastImport),
                  subtitle: Text(_lastImportSubtitle(jobs)),
                  onTap: () => context.push(Routes.importHistory),
                ),
                const Divider(height: 1),
                ListTile(
                  key: const Key('summary-last-sync'),
                  leading: const CircleAvatar(
                    radius: 16,
                    child: Icon(Icons.sync_outlined, size: 18),
                  ),
                  title: Text(appText(context).commonLastPOSSync),
                  subtitle: Text(posSyncStatus),
                  onTap: () => context.push(Routes.posSyncHistory),
                ),
                const Divider(height: 1),
                ListTile(
                  key: const Key('summary-failed'),
                  leading: const CircleAvatar(
                    radius: 16,
                    child: Icon(Icons.error_outline, size: 18),
                  ),
                  title: Text(appText(context).commonFailed),
                  subtitle: Text(
                    failedImports > 0
                        ? '$failedImports import(s) failed'
                        : 'No failures yet',
                    style: TextStyle(
                      fontSize: 12,
                      color: failedImports > 0
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  onTap: failedImports > 0
                      ? () => context.push(Routes.importHistory)
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _RecentImports(jobs: jobs),
        ],
      ),
    );
  }

  String _lastImportSubtitle(List<ImportJob> jobs) {
    if (jobs.isEmpty) return 'No imports yet';
    final latest = jobs.first;
    return '${latest.filename} • ${latest.statusLabel}';
  }

  String _integrationName(dynamic integration) {
    final name = integration is PosIntegration
        ? integration.providerName
        : 'your POS system';
    return name.isEmpty ? 'your POS system' : name;
  }

  String _lastPosSyncStatus(dynamic integration, List<dynamic> jobs) {
    if (integration == null) return 'No POS connected';
    if (jobs.isEmpty) return 'No sync history';
    final latest = jobs.first;
    final status = latest is PosSyncJob ? latest.status : 'UNKNOWN';
    final time =
        _formatDate(latest is PosSyncJob ? latest.completedAt : null);
    return '$status${time.isNotEmpty ? ' • $time' : ''}';
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    return DateFormat('d MMM yyyy, h:mm a').format(dt);
  }
}

/// "Download sample" — fetches the import template and hands it to the platform
/// save dialog. Shows a spinner while the download is in flight.
class _DownloadSampleTile extends StatelessWidget {
  const _DownloadSampleTile({required this.downloading, required this.onTap});

  final bool downloading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        key: const Key('import-tile-download-sample'),
        leading: Icon(Icons.download_outlined, color: theme.colorScheme.primary),
        title: Text(
          appText(context).commonDownloadSample,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          appText(context).importCenterScreenGetTheImportTemplateWorkbook,
          style: TextStyle(fontSize: 12),
        ),
        trailing: downloading
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.chevron_right),
        onTap: downloading ? null : onTap,
      ),
    );
  }
}

/// Reusable method-card for the hub landing surface.
class _MethodCard extends StatelessWidget {
  const _MethodCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        leading: Icon(icon, color: theme.colorScheme.primary, size: 28),
        title: Text(
          title,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.outline,
          ),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _RecentImports extends StatelessWidget {
  const _RecentImports({required this.jobs});

  final List<ImportJob> jobs;

  @override
  Widget build(BuildContext context) {
    if (jobs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(appText(context).commonRecentImports, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (final job in jobs.take(5))
                ListTile(
                  dense: true,
                  leading: Icon(
                    _statusIcon(job.status),
                    color: _statusColor(job.status, Theme.of(context)),
                    size: 20,
                  ),
                  title: Text(
                    job.filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    appText(context).importCenterScreenValidRowsValidErrorRowsErrors(job.validRows, job.errorRows),
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  IconData _statusIcon(String status) => switch (status) {
        'COMPLETED' || 'VALIDATED' => Icons.check_circle,
        'PARTIAL' => Icons.warning_amber_outlined,
        'FAILED' => Icons.error_outline,
        'PROCESSING' => Icons.sync,
        _ => Icons.schedule,
      };

  Color _statusColor(String status, ThemeData theme) {
    if (status == 'COMPLETED' || status == 'VALIDATED') {
      return AppTheme.verifiedGreen;
    }
    if (status == 'FAILED') return theme.colorScheme.error;
    return AppTheme.pendingAmber;
  }
}
