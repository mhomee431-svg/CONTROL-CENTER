import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/ui/capability_gate.dart';
import '../../../shell/capabilities_controller.dart';
import '../controllers/import_controller.dart';

/// Import Upload — File Picker + Upload Progress.
///
/// Step 1 of the import flow: pick a local .xlsx workbook, watch the upload
/// progress, and hand over to the Import Preview screen on success. The
/// shared [importControllerProvider] owns the state, so navigation between
/// the flow screens never re-uploads or loses the staged job.
class ImportUploadScreen extends ConsumerStatefulWidget {
  const ImportUploadScreen({super.key});

  @override
  ConsumerState<ImportUploadScreen> createState() =>
      _ImportUploadScreenState();
}

class _ImportUploadScreenState extends ConsumerState<ImportUploadScreen> {
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    // If a preview is already staged (deep link back into the flow), jump
    // straight to it.
    Future.microtask(() {
      if (!mounted || _navigated) return;
      if (ref.read(importControllerProvider).status == ImportStatus.preview) {
        _navigated = true;
        context.push(Routes.importPreview);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ImportState>(importControllerProvider, (prev, next) {
      // Upload finished → continue to the preview screen (exactly once).
      if (next.status == ImportStatus.preview &&
          prev?.status == ImportStatus.uploading &&
          !_navigated) {
        _navigated = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          context.push(Routes.importPreview);
        });
      }
      if (next.status == ImportStatus.error && next.message != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(next.message!)));
      }
    });

    final state = ref.watch(importControllerProvider);
    // Capability-gated (spec 103): the backend `canUploadExcel` flag decides
    // whether the picker renders at all. Read from the ONE centralized layer
    // — no plan logic here. The backend stays authoritative (the upload
    // endpoint still enforces `BULK_IMPORT` server-side).
    final caps = ref.watch(capabilitiesControllerProvider);

    return Scaffold(
      appBar: AppBar(title: Text(appText(context).commonUploadInventoryFile)),
      body: CapabilityGate(
        allowed: caps.canUploadExcel,
        title: appText(context).importUploadScreenExcelImportNotAvailableOn,
        message:
            appText(context).importUploadScreenUpgradeYourPlanToBulk,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: switch (state.status) {
                ImportStatus.uploading => _UploadingView(
                    filename: state.workbook?.name ?? 'workbook.xlsx',
                  ),
                _ => _PickView(
                    // An error keeps the flow open so the shopkeeper can retry.
                    error: state.status == ImportStatus.error
                        ? state.message
                        : null,
                    onPick: () {
                      _navigated = false;
                      ref
                          .read(importControllerProvider.notifier)
                          .pickAndUpload();
                    },
                  ),
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PickView extends StatelessWidget {
  const _PickView({required this.onPick, this.error});

  final VoidCallback onPick;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
          ),
          child: Icon(
            Icons.upload_file_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 16),
        Text(appText(context).commonChooseExcelFile,
            key: const Key('import-choose-file'),
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          appText(context).importUploadScreenOnlyXlsxWorkbooksAreAccepted,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: outline),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const Key('import-pick-button'),
          onPressed: onPick,
          icon: const Icon(Icons.folder_open_outlined),
          label: Text(appText(context).commonSelectXlsxFile),
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          Text(
            error!,
            key: const Key('import-upload-error'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

class _UploadingView extends StatelessWidget {
  const _UploadingView({required this.filename});

  final String filename;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 20),
        Text(appText(context).importUploadScreenUploading, key: const Key('import-uploading'),
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          filename,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          appText(context).importUploadScreenYourFileIsBeingChecked,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ],
    );
  }
}
