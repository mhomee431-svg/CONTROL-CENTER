import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_theme.dart';
import '../controllers/import_controller.dart';
import '../../domain/import_models.dart';

/// Import Center — the hub of the Excel inventory-import flow:
/// Download Sample → Start new import → Import history, with the status
/// vocabulary of past jobs surfaced at a glance.
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
    final downloading =
        ref.watch(sampleDownloadProvider.select((s) => s.inProgress));

    return Scaffold(
      appBar: AppBar(title: const Text('Import Center')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Bulk-update your inventory from an Excel (.xlsx) workbook. '
            'Download the sample, fill in your products, then upload it — '
            'nothing is applied until you review and confirm the preview.',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 16),
          _FlowTiles(downloading: downloading),
          const SizedBox(height: 16),
          _RecentImports(jobs: jobs),
        ],
      ),
    );
  }
}

class _FlowTiles extends ConsumerWidget {
  const _FlowTiles({required this.downloading});

  final bool downloading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            key: const Key('import-tile-download-sample'),
            leading: Icon(Icons.download_outlined,
                color: Theme.of(context).colorScheme.primary),
            title: const Text('Download sample'),
            subtitle: const Text(
              'Get the import template workbook',
              style: TextStyle(fontSize: 12),
            ),
            trailing: downloading
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            onTap: downloading
                ? null
                : () => ref.read(sampleDownloadProvider.notifier).download(),
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor),
          ListTile(
            key: const Key('import-tile-start'),
            leading: Icon(Icons.upload_file_outlined,
                color: Theme.of(context).colorScheme.primary),
            title: const Text('Start new import'),
            subtitle: const Text(
              'Pick an .xlsx file, preview it, then apply',
              style: TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // A leftover flow (e.g. after a completed import) must not
              // leak into the upload screen.
              ref.read(importControllerProvider.notifier).resetFlow();
              context.push(Routes.importUpload);
            },
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor),
          ListTile(
            key: const Key('import-tile-history'),
            leading: Icon(Icons.history_outlined,
                color: Theme.of(context).colorScheme.primary),
            title: const Text('Import history'),
            subtitle: const Text(
              'Past uploads, their rows and their outcomes',
              style: TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.importHistory),
          ),
        ],
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
        Text('Recent imports', style: Theme.of(context).textTheme.titleSmall),
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
                    '${job.validRows} valid, ${job.errorRows} errors',
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
