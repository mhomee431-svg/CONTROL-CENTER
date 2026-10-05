import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/import_models.dart';
import '../controllers/import_controller.dart';

/// Column Mapping — "Item Name -> Product Name", before anything is imported.
///
/// Two jobs, and they are the same job:
///
///  1. Show the shopkeeper what we read from THEIR sheet, in their own words. A
///     mapping they cannot reconcile with the spreadsheet in front of them is
///     worse than no mapping at all.
///  2. Let them change it. Anything the backend flagged ambiguous arrives
///     UNASSIGNED on purpose — it is the shopkeeper's call, not ours, and the
///     rows are re-validated under whatever they choose.
///
/// Nothing is applied until [InventoryImportController.remapColumns] succeeds,
/// so cancelling really does leave the staged rows untouched.
class ImportColumnMappingScreen extends ConsumerStatefulWidget {
  const ImportColumnMappingScreen({super.key});

  @override
  ConsumerState<ImportColumnMappingScreen> createState() =>
      _ImportColumnMappingScreenState();
}

/// Sentinel for "this column is not imported".
///
/// A [DropdownButton] with a genuinely null value is awkward to assert about,
/// and "don't import" is a real choice the shopkeeper must be able to make
/// explicitly — including to undo a suggestion we made.
const String kSkipColumn = '__skip__';

class _ImportColumnMappingScreenState
    extends ConsumerState<ImportColumnMappingScreen> {
  Map<int, String?> _assignment = {};
  bool _seeded = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(importControllerProvider);
    final preview = state.preview;

    if (preview == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Column Mapping')),
        body: const Center(child: Text('This import is no longer open.')),
      );
    }
    _seed(preview);

    return Scaffold(
      appBar: AppBar(title: const Text('Column Mapping')),
      body: Column(
        children: [
          _Header(preview: preview, undecided: _undecided(preview)),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              itemCount: preview.columnProposal.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) => _ColumnRow(
                key: Key('import-map-row-${preview.columnProposal[i].columnIndex}'),
                proposal: preview.columnProposal[i],
                assigned: _assignment[preview.columnProposal[i].columnIndex],
                options: _fieldNames(preview, state.schema),
                enabled: !state.remapping,
                onChanged: (value) => setState(() {
                  _assignment[preview.columnProposal[i].columnIndex] = value;
                }),
              ),
            ),
          ),
          _MappingActions(
            canSave: _undecided(preview) == 0,
            saving: state.remapping,
            error: state.mappingError,
            onCancel: () => context.pop(),
            onSave: _save,
          ),
        ],
      ),
    );
  }

  /// Seed the draft from the mapping the ROWS are actually using.
  ///
  /// Once, and from `columnMapping` rather than from the suggestions: the
  /// shopkeeper may already have corrected this, and re-proposing the original
  /// guess would silently undo their answer.
  void _seed(ImportPreview preview) {
    if (_seeded) return;
    _assignment = preview.initialAssignment();
    _seeded = true;
  }

  /// Ambiguous columns the shopkeeper still has to settle: the blocker.
  ///
  /// A contested column stops blocking once ANOTHER column has claimed the
  /// field it was fighting over. The choice has then been made, by
  /// elimination, and the leftover column simply stays unmapped. It still
  /// shows its reason, because refusing to guess is a fact worth seeing, but
  /// it does not demand a second tap to say "don't import" -- that would be
  /// nagging rather than clarifying.
  int _undecided(ImportPreview preview) {
    final claimed = _assignment.values.whereType<String>().toSet();
    return preview.columnProposal.where((p) {
      if (!p.isAmbiguous || _assignment[p.columnIndex] != null) {
        return false;
      }
      return !p.candidates.any(claimed.contains);
    }).length;
  }

  /// Every field the shopkeeper may choose, as `name -> label`.
  ///
  /// From the backend schema so the vocabulary is the one the validator uses.
  /// The fallback (schema not loaded) is the union of what the backend itself
  /// proposed for these columns — still the server's vocabulary, just a partial
  /// one, and better than a list invented here.
  List<MapEntry<String, String>> _fieldNames(
    ImportPreview preview,
    ImportSchema? schema,
  ) {
    final entries = <String, String>{};
    for (final f in schema?.fields ?? const <ImportSchemaField>[]) {
      entries[f.name] = f.label;
    }
    if (entries.isEmpty) {
      for (final p in preview.columnProposal) {
        for (final name in [
          if (p.suggestedField != null) p.suggestedField!,
          ...p.candidates,
        ]) {
          entries.putIfAbsent(
            name,
            () => name
                .split('_')
                .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
                .join(' '),
          );
        }
      }
    }
    final list = entries.entries.toList();
    list.sort((a, b) => a.value.compareTo(b.value));
    return list;
  }

  Future<void> _save() async {
    final ok = await ref
        .read(importControllerProvider.notifier)
        .remapColumns(_assignment);
    if (!mounted) return;
    if (ok) context.pop();
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.preview, required this.undecided});

  final ImportPreview preview;
  final int undecided;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Match each column to the field it should fill in.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          if (undecided > 0)
            Container(
              key: const Key('import-map-warning'),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.pendingAmber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.pendingAmber.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: AppTheme.pendingAmber,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$undecided ${undecided == 1 ? 'column needs' : 'columns need'} '
                      'your choice ? we will not guess which one you meant.',
                      key: const Key('import-map-warning-text'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One row of the mapping: the shopkeeper's header -> a HyperLocal field.
class _ColumnRow extends StatelessWidget {
  const _ColumnRow({
    required this.proposal,
    required this.assigned,
    required this.options,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final ImportColumnProposal proposal;
  final String? assigned;
  final List<MapEntry<String, String>> options;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = assigned ?? kSkipColumn;
    DropdownMenuItem<String> itemFor(String value, String label) =>
        DropdownMenuItem<String>(
          value: value,
          child: Text(label, overflow: TextOverflow.ellipsis),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      proposal.header,
                      key: Key('import-map-header-${proposal.columnIndex}'),
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'Column ${proposal.columnLetter}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.arrow_forward, size: 16),
              ),
              Expanded(
                flex: 6,
                child: DropdownButtonFormField<String>(
                  key: Key('import-map-field-${proposal.columnIndex}'),
                  initialValue: options.any((o) => o.key == selected)
                      ? selected
                      : kSkipColumn,
                  isExpanded: true,
                  onChanged: enabled
                      ? (value) => onChanged(value == kSkipColumn ? null : value)
                      : null,
                  items: [
                    itemFor(kSkipColumn, "Don't import"),
                    ...options.map((o) => itemFor(o.key, o.value)),
                  ],
                ),
              ),
            ],
          ),
          if (proposal.isAmbiguous && assigned == null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                proposal.ambiguityReason,
                key: Key('import-map-reason-${proposal.columnIndex}'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.pendingAmber,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MappingActions extends StatelessWidget {
  const _MappingActions({
    required this.canSave,
    required this.saving,
    required this.error,
    required this.onCancel,
    required this.onSave,
  });

  final bool canSave;
  final bool saving;
  final String? error;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  error!,
                  key: const Key('import-map-error'),
                  style: const TextStyle(fontSize: 12, color: AppTheme.rejectedRed),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('import-map-cancel'),
                    onPressed: saving ? null : onCancel,
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    key: const Key('import-map-save'),
                    onPressed: (canSave && !saving) ? onSave : null,
                    child: saving
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save & re-check rows'),
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
