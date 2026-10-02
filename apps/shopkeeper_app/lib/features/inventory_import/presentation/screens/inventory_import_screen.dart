import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../core/state/system_state.dart';
import '../../../../core/state/system_state_view.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/capability_gate.dart';
import '../../../shell/capabilities_controller.dart';
import '../../domain/import_models.dart';
import '../controllers/import_controller.dart';

/// Excel inventory import screen (Phase 24 Part B).
///
/// Flow: pick workbook → upload (server-side validation) → preview row-level
/// outcomes → confirm → done. Recent jobs are shown at the bottom.
class InventoryImportScreen extends ConsumerStatefulWidget {
  const InventoryImportScreen({super.key});
 
  @override
  ConsumerState<InventoryImportScreen> createState() =>
      _InventoryImportScreenState();
}

class _InventoryImportScreenState extends ConsumerState<InventoryImportScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(importControllerProvider.notifier).loadJobs(),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ImportState>(importControllerProvider, (prev, next) {
      if (next.status == ImportStatus.done && next.result != null) {
        final result = next.result!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.queued
                  ? '${result.processed} products queued for import'
                  : '${result.processed} products imported (${result.failed} skipped)',
            ),
          ),
        );
      }
      if (next.status == ImportStatus.error && next.message != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(next.message!)));
      }
    });

    // Download Sample outcome — a separate flow, so a separate listener.
    ref.listen<SampleDownloadState>(sampleDownloadProvider, (prev, next) {
      final message = next.message;
      if (message != null && prev?.message != message) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
        ref.read(sampleDownloadProvider.notifier).clearMessage();
      }
    });

    final state = ref.watch(importControllerProvider);
    final sampleDownload = ref.watch(sampleDownloadProvider);
    final uploading = state.status == ImportStatus.uploading;
    final confirming = state.status == ImportStatus.confirming;
    final saving = uploading || confirming;
    // Capability-gated (spec 103): the backend `canUploadExcel` flag decides
    // whether the whole upload surface renders. Read from the ONE centralized
    // layer — no plan logic here. The backend stays authoritative (the import
    // endpoint still enforces `BULK_IMPORT` server-side).
    final caps = ref.watch(capabilitiesControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Import from Excel'),
        actions: [
          if (state.status == ImportStatus.preview ||
              state.status == ImportStatus.idle)
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              tooltip: 'Refresh recent imports',
              onPressed: saving
                  ? null
                  : () =>
                        ref.read(importControllerProvider.notifier).loadJobs(),
            ),
        ],
      ),
      body: CapabilityGate(
        allowed: caps.canUploadExcel,
        title: 'Excel import not available on your plan',
        message:
            'Upgrade your plan to bulk-import a workbook. Your current plan '
            'does not include bulk import.',
        child: SafeArea(
          child: switch (state.status) {
            ImportStatus.idle => _IdleView(
              onImportTap: saving ? null : _pickAndUpload,
              hasJobs: state.jobs.isNotEmpty,
              onDownloadSample:
                  sampleDownload.inProgress ? null : _downloadSample,
              downloadingSample: sampleDownload.inProgress,
            ),
            ImportStatus.uploading => const _UploadingView(),
            ImportStatus.preview => _PreviewView(
              preview: state.preview!,
              onConfirm: saving ? null : _confirm,
              onCancel: saving ? null : _cancelFlow,
              saving: saving,
            ),
            ImportStatus.confirming =>
              _ConfirmingView(preview: state.preview!),
            ImportStatus.done => _DoneView(
              result: state.result!,
              onImportAnother: () =>
                  ref.read(importControllerProvider.notifier).resetFlow(),
            ),
            ImportStatus.error => _ErrorView(
              message: state.message ?? 'Something went wrong.',
              onRetry: () =>
                  ref.read(importControllerProvider.notifier).resetFlow(),
            ),
          },
        ),
      ),
    );
  }

  Future<void> _pickAndUpload() async {
    setState(() {});
    await ref.read(importControllerProvider.notifier).pickAndUpload();
    // The picker/upload can outlive this screen (user navigates back while the
    // file dialog or the upload is in flight); never touch state after dispose.
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _confirm() async {
    await ref.read(importControllerProvider.notifier).confirm();
    if (!mounted) return;
    setState(() {});
  }

  void _cancelFlow() {
    ref.read(importControllerProvider.notifier).resetFlow();
    setState(() {});
  }

  /// Download Sample — fetches the template workbook and offers the platform
  /// save dialog. The outcome surfaces through the controller's message.
  Future<void> _downloadSample() async {
    if (ref.read(sampleDownloadProvider).inProgress) return;
    await ref.read(sampleDownloadProvider.notifier).download();
    // The download (plus the platform save dialog) can outlive this screen.
    if (!mounted) return;
    setState(() {});
  }
}

// ── Idle: empty state + import CTA ─────────────────────────────────────────

class _IdleView extends StatelessWidget {
  const _IdleView({
    required this.onImportTap,
    required this.hasJobs,
    required this.onDownloadSample,
    required this.downloadingSample,
  });

  final VoidCallback? onImportTap;
  final bool hasJobs;
  final VoidCallback? onDownloadSample;
  final bool downloadingSample;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.file_present_outlined, size: 64, color: scheme.outline),
            const SizedBox(height: 16),
            Text(
              'Import products from Excel',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Upload an .xlsx workbook to bulk-add or update your shop\'s '
              'inventory. The file is validated before you commit changes.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.outline),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onImportTap,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Choose Excel file'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onDownloadSample,
              icon: downloadingSample
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined),
              label: Text(
                downloadingSample ? 'Downloading...' : 'Download sample',
              ),
            ),
            if (hasJobs) ...[
              const SizedBox(height: 24),
              const _RecentJobsMiniList(),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Uploading: progress indicator ───────────────────────────────────────────

class _UploadingView extends StatelessWidget {
  const _UploadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Validating your file...'),
        ],
      ),
    );
  }
}

// ── Preview: row-level outcomes + confirm ──────────────────────────────────

class _PreviewView extends StatelessWidget {
  const _PreviewView({
    required this.preview,
    required this.onConfirm,
    required this.onCancel,
    required this.saving,
  });

  final ImportPreview preview;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final errors = preview.rows.where((r) => r.isError).toList();
    final meta = preview.meta;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _SummaryChip(
                label: 'Total',
                value: meta.totalRows,
                color: Theme.of(context).colorScheme.primary,
              ),
              _SummaryChip(
                label: 'Valid',
                value: meta.validRows,
                color: AppTheme.verifiedGreen,
              ),
              _SummaryChip(
                label: 'Errors',
                value: meta.errorRows,
                color: AppTheme.rejectedRed,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: errors.isEmpty
              ? ListView(
                  children: const [
                    Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'All rows validated successfully.\n'
                        'Review the summary above and confirm to apply changes.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                )
              : ListView.separated(
                  itemCount: errors.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final row = errors[i];
                    return ListTile(
                      dense: true,
                      leading: const CircleFlags(
                        Icons.error_outline,
                        AppTheme.rejectedRed,
                      ),
                      title: Text(
                        'Row ${row.rowNumber}',
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        row.errorMessage ?? row.errorCode ?? 'Unknown error',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: saving ? null : onCancel,
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: saving ? null : onConfirm,
                  icon: saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outlined),
                  label: Text(saving ? 'Applying...' : 'Confirm import'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Confirming: final processing ───────────────────────────────────────────

class _ConfirmingView extends StatelessWidget {
  const _ConfirmingView({required this.preview});

  final ImportPreview preview;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              preview.meta.totalRows > 200
                  ? 'Processing ${preview.meta.totalRows} rows in the background...'
                  : 'Applying your inventory changes...',
            ),
          ],
        ),
      ),
    );
  }
}

// ── Done: success summary ──────────────────────────────────────────────────

class _DoneView extends StatelessWidget {
  const _DoneView({required this.result, required this.onImportAnother});

  final ImportConfirmResult result;
  final VoidCallback onImportAnother;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final failedText = result.failed > 0 ? ' (${result.failed} skipped)' : '';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.check_circle,
              size: 64,
              color: AppTheme.verifiedGreen,
            ),
            const SizedBox(height: 16),
            Text(
              result.queued ? 'Import queued' : 'Import complete',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              result.queued
                  ? '${result.processed} products are being processed '
                        'and will be available shortly.'
                  : '${result.processed} product${result.processed == 1 ? '' : 's'} '
                        'imported successfully$failedText.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.outline),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onImportAnother,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Import another file'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Error: the shared system-state renderer + the import flow's own retry ────
//
// The retry label stays "Try again" (restarting the import flow, not re-hitting
// the same request), while the icon/way-out still match the real cause — an
// offline failure or a backend maintenance window read differently from a bug.
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final carried = SystemStateSpec.fromMessage(message);
    return SystemStateView(
      spec: carried != null
          ? SystemStateSpec.of(carried, appText(context))
          : SystemStateSpec(
              state: SystemState.genericRetry,
              title: 'Import failed',
              message: message,
              icon: Icons.cloud_off_outlined,
              action: SystemAction.retry,
            ),
      onRetry: onRetry,
      retryLabel: 'Try again',
    );
  }
}

// ── Mini recent-jobs list ──────────────────────────────────────────────────

class _RecentJobsMiniList extends ConsumerWidget {
  const _RecentJobsMiniList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(importControllerProvider.select((s) => s.jobs));
    if (jobs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Recent imports', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: jobs.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final job = jobs[i];
            return ListTile(
              dense: true,
              leading: CircleFlags(
                _statusIcon(job.status),
                _statusColor(job.status, Theme.of(context)),
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
            );
          },
        ),
      ],
    );
  }

  IconData _statusIcon(String status) {
    return switch (status) {
      'COMPLETED' || 'VALIDATED' => Icons.check_circle,
      'PARTIAL' => Icons.warning_amber_outlined,
      'FAILED' => Icons.error_outline,
      'PROCESSING' => Icons.sync,
      _ => Icons.schedule,
    };
  }

  Color _statusColor(String status, ThemeData theme) {
    if (status == 'COMPLETED' || status == 'VALIDATED') {
      return AppTheme.verifiedGreen;
    }
    if (status == 'FAILED') return theme.colorScheme.error;
    return AppTheme.pendingAmber;
  }
}

// ── Summary chip (used in preview bar) ─────────────────────────────────────

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Text(
            '$value',
            style: TextStyle(fontWeight: FontWeight.w700, color: color),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.9)),
          ),
        ],
      ),
    );
  }
}

// ── Small flag-circle leading widget ───────────────────────────────────────

class CircleFlags extends StatelessWidget {
  const CircleFlags(this.icon, this.color, {super.key});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: 10,
    backgroundColor: color.withValues(alpha: 0.12),
    child: Icon(icon, size: 11, color: color),
  );
}
