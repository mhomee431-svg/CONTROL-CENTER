import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/import_models.dart';

/// Which rows the report lists.
enum ReportFilter { all, errors }

/// Row-level report for a single import job.
///
/// Shared by two surfaces so the wording and layout never drift:
///   * Import history — tapping a past job opens it on [ReportFilter.all].
///   * Import processing — "View Results" / "View Errors" open it on
///     [ReportFilter.all] / [ReportFilter.errors] respectively.
///
/// Rows come straight from the backend report, so failures are shown with the
/// server's own error code and message — partial failures are never hidden.
class ImportReportSheet extends StatefulWidget {
  const ImportReportSheet({
    super.key,
    required this.job,
    required this.future,
    this.initialFilter = ReportFilter.all,
  });

  final ImportJob job;

  /// The job's report payload (rows + counters).
  final Future<ImportPreview> future;

  /// Filter selected when the sheet opens.
  final ReportFilter initialFilter;

  @override
  State<ImportReportSheet> createState() => _ImportReportSheetState();
}
class _ImportReportSheetState extends State<ImportReportSheet> {
  late ReportFilter _filter = widget.initialFilter;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: FutureBuilder<ImportPreview>(
          future: widget.future,
          builder: (context, snap) {
            final header = _Header(job: widget.job);

            if (snap.connectionState != ConnectionState.done) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    header,
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  ],
                ),
              );
            }

            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    header,
                    Text(
                      'Could not load the report for this import.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ),
              );
            }

            final allRows = snap.data?.rows ?? const <ImportRow>[];
            final errorRows = allRows.where((r) => r.isError).toList();
            final visible = _filter == ReportFilter.all ? allRows : errorRows;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                header,
                _FilterBar(
                  total: allRows.length,
                  errors: errorRows.length,
                  selected: _filter,
                  onChanged: (f) => setState(() => _filter = f),
                ),
                Flexible(
                  child: visible.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            _filter == ReportFilter.errors
                                ? 'No failed rows for this import.'
                                : 'No row-level details recorded for this '
                                      'import.',
                            key: const Key('import-report-empty'),
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                          itemCount: visible.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, i) =>
                              _ReportRowTile(row: visible[i]),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Job filename + status/summary line shown above the row list.
class _Header extends StatelessWidget {
  const _Header({required this.job});

  final ImportJob job;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            job.filename,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '${job.statusLabel} · ${job.totalRows} rows · '
            '${job.successRows} success, ${job.failedRowCount} failed',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

/// All / Errors switch, each carrying its live row count.
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.total,
    required this.errors,
    required this.selected,
    required this.onChanged,
  });

  final int total;
  final int errors;
  final ReportFilter selected;
  final ValueChanged<ReportFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Row(
        children: [
          ChoiceChip(
            key: const Key('import-report-filter-all'),
            label: Text('All rows ($total)'),
            selected: selected == ReportFilter.all,
            onSelected: (_) => onChanged(ReportFilter.all),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            key: const Key('import-report-filter-errors'),
            label: Text('Failed ($errors)'),
            selected: selected == ReportFilter.errors,
            onSelected: (_) => onChanged(ReportFilter.errors),
          ),
        ],
      ),
    );
  }
}

/// One row of the report — valid rows read as "Valid", failures show the
/// server's error code and message verbatim.
class _ReportRowTile extends StatelessWidget {
  const _ReportRowTile({required this.row});

  final ImportRow row;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        row.isError ? Icons.error_outline : Icons.check_circle_outline,
        color: row.isError ? AppTheme.rejectedRed : AppTheme.verifiedGreen,
        size: 18,
      ),
      title: Text(
        'Row ${row.rowNumber}'
        '${row.productName == null ? '' : ' · ${row.productName}'}',
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: row.isError
          ? Text(
              '${row.errorCode ?? 'ERROR'} — '
              '${row.errorMessage ?? 'Invalid row'}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            )
          : const Text('Valid', style: TextStyle(fontSize: 12)),
    );
  }
}
