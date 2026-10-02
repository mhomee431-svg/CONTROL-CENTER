import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/state/system_state_view.dart';
import '../../../../core/theme/app_theme.dart';
import '../controllers/import_controller.dart';
import '../../domain/import_models.dart';

/// Import Preview — the staged job's row-level outcomes BEFORE anything is
/// applied: a summary bar (total / valid / errors), the validation errors and
/// the Confirm action that moves the flow to Import Processing.
class ImportPreviewScreen extends ConsumerStatefulWidget {
  const ImportPreviewScreen({super.key});

  @override
  ConsumerState<ImportPreviewScreen> createState() =>
      _ImportPreviewScreenState();
}

class _ImportPreviewScreenState extends ConsumerState<ImportPreviewScreen> {
  bool _errorsOnly = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(importControllerProvider);
    final preview = state.preview;

    return Scaffold(
      appBar: AppBar(title: Text(appText(context).commonReviewImport)),
      body: preview == null
          ? _NoPreviewView(
              onBack: () {
                ref.read(importControllerProvider.notifier).resetFlow();
                context.go(Routes.importCenter);
              },
            )
          : _PreviewBody(
              preview: preview,
              errorsOnly: _errorsOnly,
              onToggleErrorsOnly: (v) => setState(() => _errorsOnly = v),
              onConfirm: () => context.push(Routes.importProcessing),
              onDiscard: () {
                ref.read(importControllerProvider.notifier).resetFlow();
                context.go(Routes.importCenter);
              },
            ),
    );
  }
}

class _NoPreviewView extends StatelessWidget {
  const _NoPreviewView({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SystemStateView.empty(
      title: appText(context).commonNothingToPreview,
      icon: Icons.folder_off_outlined,
      action: FilledButton(
        onPressed: onBack,
        child: Text(appText(context).commonBackToImportCenter),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.value,
    required this.color,
    super.key,
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(appText(context).importPreviewScreenValue(value),
              style: TextStyle(fontWeight: FontWeight.w700, color: color)),
          const SizedBox(width: 4),
          Text(
            label,
            style:
                TextStyle(fontSize: 12, color: color.withValues(alpha: 0.9)),
          ),
        ],
      ),
    );
  }
}

class _PreviewBody extends StatelessWidget {
  const _PreviewBody({
    required this.preview,
    required this.errorsOnly,
    required this.onToggleErrorsOnly,
    required this.onConfirm,
    required this.onDiscard,
  });

  final ImportPreview preview;
  final bool errorsOnly;
  final ValueChanged<bool> onToggleErrorsOnly;
  final VoidCallback onConfirm;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final meta = preview.meta;
    final rows = preview.rows;
    final visible = errorsOnly
        ? rows.where((r) => r.isError).toList(growable: false)
        : rows;

    return Column(
      children: [
        // ── Summary bar ─────────────────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).colorScheme.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                meta.filename,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _SummaryChip(
                    key: const Key('import-chip-total'),
                    label: appText(context).commonRows,
                    value: meta.totalRows,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  _SummaryChip(
                    key: const Key('import-chip-valid'),
                    label: appText(context).commonValid,
                    value: preview.validCount,
                    color: AppTheme.verifiedGreen,
                  ),
                  _SummaryChip(
                    key: const Key('import-chip-errors'),
                    label: appText(context).commonErrors,
                    value: preview.errorCount,
                    color: preview.errorCount > 0
                        ? AppTheme.rejectedRed
                        : AppTheme.verifiedGreen,
                  ),
                  // §41 lists Duplicate Rows as its own count, separate from
                  // errors. Shown only when the payload carried row detail, so a
                  // summarised large import never displays a "0 duplicates"
                  // the app cannot actually vouch for.
                  if (preview.duplicateCount > 0)
                    _SummaryChip(
                      key: const Key('import-chip-duplicates'),
                      label: 'Duplicates',
                      value: preview.duplicateCount,
                      color: AppTheme.pendingAmber,
                    ),
                ],
              ),
              // The backend deduplicates identical uploads, so this preview can
              // belong to an EARLIER job rather than the file just picked.
              // Saying so is the difference between reviewing your own file and
              // reviewing a ghost of it (§40: never push an unreviewed file).
              if (preview.isIdempotentReplay)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Container(
                    key: const Key('import-replay-notice'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.pendingAmber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppTheme.pendingAmber.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline,
                            size: 18, color: AppTheme.pendingAmber),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'This exact file was already uploaded, so these '
                            'are the rows from that earlier import. Pick a '
                            'changed file to import different rows.',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Text(
                    errorsOnly
                        ? 'No validation errors in this file'
                        : 'No rows found in this file',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _RowTile(row: visible[i]),
                ),
        ),
        _PreviewActions(
          preview: preview,
          errorsOnly: errorsOnly,
          onToggleErrorsOnly: onToggleErrorsOnly,
          onConfirm: onConfirm,
          onDiscard: onDiscard,
        ),
      ],
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({required this.row});

  final ImportRow row;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(
        row.isError ? Icons.error_outline : Icons.check_circle_outline,
        color: row.isError ? AppTheme.rejectedRed : AppTheme.verifiedGreen,
        size: 20,
      ),
      title: Text(
        appText(context).importPreviewScreenRowRowNumberValue(row.rowNumber, row.productName == null ? '' : ' · ${row.productName}'),
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: row.isError
          ? Text(
              // §42 wants Row / Field / Error. The backend sends `error_field`
              // ("barcode", "price", "row", …) and it used to be dropped, so the
              // shopkeeper saw a bare code with nothing pointing at the cell.
              [
                if (row.errorField != null && row.errorField!.isNotEmpty)
                  row.errorField!,
                row.errorCode ?? 'ERROR',
                if (row.errorMessage != null && row.errorMessage!.isNotEmpty)
                  row.errorMessage!,
              ].join(' · '),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            )
          : Text(
              appText(context).importPreviewScreenValidWillBeAppliedTo,
              style: TextStyle(fontSize: 12),
            ),
    );
  }
}

class _PreviewActions extends StatelessWidget {
  const _PreviewActions({
    required this.preview,
    required this.errorsOnly,
    required this.onToggleErrorsOnly,
    required this.onConfirm,
    required this.onDiscard,
  });

  final ImportPreview preview;
  final bool errorsOnly;
  final ValueChanged<bool> onToggleErrorsOnly;
  final VoidCallback onConfirm;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (preview.errorCount > 0)
              SwitchListTile(
                key: const Key('import-errors-toggle'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(appText(context).importPreviewScreenShowOnlyValidationErrors),
                value: errorsOnly,
                onChanged: onToggleErrorsOnly,
              ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('import-discard'),
                    onPressed: onDiscard,
                    child: Text(appText(context).commonDiscard),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    key: const Key('import-confirm'),
                    onPressed: preview.validCount == 0 ? null : onConfirm,
                    child: Text(
                      preview.errorCount > 0
                          ? 'Apply valid rows'
                          : 'Apply import',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
