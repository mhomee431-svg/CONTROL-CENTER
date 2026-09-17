/// Domain models for the Excel inventory-import feature (Phase 24 Part B).
///
/// Maps the backend `/shopkeeper/shops/{id}/inventory-imports` contract:
/// upload → preview (row-level validation) → confirm → report.
library;

/// One staged import job (upload preview or a listed past job).
class ImportJob {
  const ImportJob({
    required this.id,
    required this.filename,
    required this.status,
    required this.totalRows,
    required this.validRows,
    required this.errorRows,
  });

  final int id;
  final String filename;

  /// VALIDATING / VALIDATED / PROCESSING / COMPLETED / PARTIAL / FAILED.
  final String status;
  final int totalRows;
  final int validRows;
  final int errorRows;

  bool get hasErrors => errorRows > 0;
  bool get isConfirmed =>
      status == 'COMPLETED' || status == 'PROCESSING' || status == 'PARTIAL';

  factory ImportJob.fromJson(Map<String, dynamic> json) => ImportJob(
    id: (json['id'] as num?)?.toInt() ?? 0,
    filename: json['filename'] as String? ?? '',
    status: json['status'] as String? ?? 'VALIDATING',
    totalRows: (json['total_rows'] as num?)?.toInt() ?? 0,
    validRows: (json['valid_rows'] as num?)?.toInt() ?? 0,
    errorRows: (json['error_rows'] as num?)?.toInt() ?? 0,
  );
}

/// One row of the import preview (valid or error with a reason).
class ImportRow {
  const ImportRow({
    required this.rowNumber,
    required this.status,
    this.productName,
    this.errorCode,
    this.errorMessage,
  });

  final int rowNumber;

  /// VALID / ERROR.
  final String status;
  final String? productName;
  final String? errorCode;
  final String? errorMessage;

  bool get isError => status == 'ERROR';

  factory ImportRow.fromJson(Map<String, dynamic> json) => ImportRow(
    rowNumber: (json['row_number'] as num?)?.toInt() ?? 0,
    status: json['status'] as String? ?? 'VALID',
    productName: (json['product_name'] ?? json['name']) as String?,
    errorCode: json['error_code'] as String?,
    errorMessage: json['error_message'] as String?,
  );
}

/// Full preview payload for one job (meta + row-level outcomes).
class ImportPreview {
  const ImportPreview({required this.meta, this.rows = const []});

  final ImportJob meta;
  final List<ImportRow> rows;

  /// Rows that will be applied to inventory.
  ///
  /// The staged payload may omit row-level detail (large imports are summarised
  /// by the job counters only), so the job's own `valid_rows` / `error_rows`
  /// are the fallback — the Confirm action must never be disabled just because
  /// the preview did not ship a `report.rows` array.
  int get validCount =>
      rows.isEmpty ? meta.validRows : rows.where((r) => !r.isError).length;
  int get errorCount =>
      rows.isEmpty ? meta.errorRows : rows.where((r) => r.isError).length;

  factory ImportPreview.fromJson(Map<String, dynamic> json) {
    final meta = ImportJob.fromJson(json);
    final reportRows =
        ((json['report'] as Map<String, dynamic>?)?['rows']
            as List<dynamic>?) ??
        (json['rows'] as List<dynamic>?);
    return ImportPreview(
      meta: meta,
      rows: (reportRows ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ImportRow.fromJson)
          .toList(growable: false),
    );
  }
}

/// Result after confirming an import (processed counts from the backend).
class ImportConfirmResult {
  const ImportConfirmResult({
    required this.processed,
    required this.failed,
    this.queued = false,
  });

  final int processed;
  final int failed;

  /// Large imports are queued for background processing.
  final bool queued;

  factory ImportConfirmResult.fromJson(Map<String, dynamic> json) =>
      ImportConfirmResult(
        processed:
            (json['processed'] as num?)?.toInt() ??
            (json['processed_rows'] as num?)?.toInt() ??
            0,
        failed: (json['failed'] as num?)?.toInt() ?? 0,
        queued: json['queued'] as bool? ?? false,
      );
}

/// A locally-picked .xlsx workbook ready for upload.
class PickedWorkbook {
  const PickedWorkbook({required this.path, required this.name});

  final String path;
  final String name;

  String get extension =>
      name.contains('.') ? name.split('.').last.toLowerCase() : '';
}
