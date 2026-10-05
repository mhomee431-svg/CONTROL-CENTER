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
  bool _mappingOpen = false;

  @override
  void initState() {
    super.initState();
    // The Column Mapping step renders the backend's import schema — field
    // names, accepted header spellings, and the rules each field is checked
    // against. Fetching it HERE (not at upload) keeps it as the vocabulary the
    // preview is judged against, and loadSchema() is a no-op once it is held.
    Future.microtask(
      () => ref.read(importControllerProvider.notifier).loadSchema(),
    );
  }

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
              schema: state.schema,
              mappingOpen: _mappingOpen,
              onToggleMapping: (v) => setState(() => _mappingOpen = v),
              onEditMapping: () => context.push(Routes.importColumnMapping),
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
    this.schema,
    this.mappingOpen = false,
    this.onToggleMapping,
    this.onEditMapping,
  });

  final ImportPreview preview;

  /// Backend import schema, when it loaded — null renders the mapping panel
  /// from the upload's `column_mapping` alone (fewer rules, never wrong ones).
  final ImportSchema? schema;
  final bool mappingOpen;
  final ValueChanged<bool>? onToggleMapping;
  final VoidCallback? onEditMapping;
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

    // The Column below shares its height between the summary bar, the
    // mapping panel, the row list and the action bar. The panel is a
    // FIXED-height child (the row list is the Expanded one), so it must be
    // told how much room is left: measuring against the SCREEN instead of
    // this box overflows on short devices and on a 600dp test surface alike.
    return LayoutBuilder(
      builder: (context, constraints) => Column(
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
        _ColumnMappingPanel(
          preview: preview,
          schema: schema,
          open: mappingOpen,
          onToggle: onToggleMapping ?? (_) {},
          // Under a third of the body: the summary and the action bar take a
          // fixed ~250dp together, and the panel scrolls rather than pushing
          // the row list off-screen.
          maxContentHeight: constraints.maxHeight * 0.3,
          onEdit: onEditMapping,
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
      ),
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


/// Column Mapping — how the uploaded header row was read.
///
/// This is the spec's "Column Mapping" step rendered as an inspectable panel
/// rather than a wizard: the mapping has already been decided by the server the
/// moment the file was parsed, so a screen that let the shopkeeper "change" it
/// would be theatre — the staged rows would not follow. What is useful is the
/// truth: which column supplied each field, which header spellings are
/// accepted, and what each field is required to satisfy.
///
/// Everything except the position comes from `GET ?/inventory-imports/schema`,
/// so a rule change on the backend changes this panel with no app release.
class _ColumnMappingPanel extends StatelessWidget {
  const _ColumnMappingPanel({
    required this.preview,
    required this.schema,
    required this.open,
    required this.onToggle,
    required this.maxContentHeight,
    this.onEdit,
  });

  /// Opens the Column Mapping screen for correction.
  final VoidCallback? onEdit;

  final ImportPreview preview;
  final ImportSchema? schema;
  final bool open;
  final ValueChanged<bool> onToggle;

  /// Height cap for the EXPANDED content (the tile header is extra). Scrolling
  /// within this cap is what keeps a ten-field mapping from overflowing.
  final double maxContentHeight;

  /// Pseudo-fields for the columns the upload mapped, in column order — used
  /// when the schema could not be fetched. Carries no rules, because the only
  /// honest source of those is the backend.
  static List<ImportSchemaField> _mappedOnly(Map<String, int> mapping) {
    final names = mapping.keys.toList()
      ..sort((a, b) {
        final ia = mapping[a] ?? -1, ib = mapping[b] ?? -1;
        return ia == ib ? a.compareTo(b) : ia.compareTo(ib);
      });
    return [
      for (final n in names)
        ImportSchemaField(
          name: n,
          label: n
              .split('_')
              .where((w) => w.isNotEmpty)
              .map((w) => w[0].toUpperCase() + w.substring(1))
              .join(' '),
          rules: const [],
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final mapping = preview.columnMapping;
    if (mapping.isEmpty) return const SizedBox.shrink();

    final fields = schema?.fields ?? const <ImportSchemaField>[];
    final theme = Theme.of(context);
    // With no schema loaded there is no field vocabulary to enumerate, so the
    // panel lists ONLY what this upload actually mapped (ordered by position).
    // Synthesising the full field list here would mean writing the rules down a
    // second time in the client — the drift this step exists to avoid.
    final shown = fields.isNotEmpty ? fields : _mappedOnly(mapping);
    final mapped = shown.where((f) => f.mappedIn(mapping)).length;
    final total = shown.length;

    // A Material (not a decorated Container) is the tile's own surface: an
    // ExpansionTile paints its ink on the nearest Material ancestor, so
    // decorating a Container instead leaves the tap highlight invisible.
    final ambiguous = preview.ambiguousColumns.length;

    return Material(
      color: theme.colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const Key('import-column-mapping'),
          initiallyExpanded: open,
          onExpansionChanged: onToggle,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          title: Row(
            children: [
              Text(
                'Column Mapping',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              Text(
                '$mapped of $total',
                key: const Key('import-mapping-count'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              if (ambiguous > 0) ...[
                const SizedBox(width: 8),
                Text(
                  '$ambiguous to confirm',
                  key: const Key('import-mapping-ambiguous'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.pendingAmber,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
          children: [
            // Ten fields with their aliases and rules are taller than the
            // preview's row list, so the expanded panel scrolls inside a
            // bounded box instead of pushing the row list off the screen.
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxContentHeight),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (schema == null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Column rules could not be loaded, so only the '
                          'columns read from this file are shown.',
                          key: const Key('import-mapping-noschema'),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.outline),
                        ),
                      ),
                    ...shown.map((f) => _MappingTile(field: f, mapping: mapping)),
                    if (schema != null &&
                        schema!.requiredAnyOf.isNotEmpty &&
                        schema!.requiredAnyOf
                            .every((n) => !mapping.containsKey(n)))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Needs at least one of: '
                          '${schema!.requiredAnyOf.join(", ")}',
                          key: const Key('import-mapping-required'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppTheme.rejectedRed,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    // Inspecting the mapping is only half the step; the other
                    // half is being able to change it. Without this the panel
                    // would show a contested column with no way to resolve it
                    // except re-editing the spreadsheet and re-uploading.
                    if (onEdit != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: const Key('import-mapping-edit'),
                          onPressed: onEdit,
                          icon: const Icon(Icons.tune, size: 18),
                          label: const Text('Change column mapping'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One field of the mapping: label, the column it was read from (or nothing),
/// the accepted header spellings, and the server's rules for it.
class _MappingTile extends StatelessWidget {
  const _MappingTile({required this.field, required this.mapping});

  final ImportSchemaField field;
  final Map<String, int> mapping;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final column = field.columnLabel(mapping);
    final rules = field.rules;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  field.label,
                  key: Key('import-mapping-label-${field.name}'),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                key: Key('import-mapping-column-${field.name}'),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (column == null
                          ? AppTheme.rejectedRed
                          : AppTheme.verifiedGreen)
                      .withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  column ?? 'Not in this file',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: column == null
                        ? AppTheme.rejectedRed
                        : AppTheme.verifiedGreen,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (field.aliases.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Also accepts: ${field.aliases.join(", ")}',
                key: Key('import-mapping-aliases-${field.name}'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
          if (rules.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: rules
                    .map(
                      (r) => Text(
                        r,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
        ],
      ),
    );
  }
}
