/// Domain models for the Excel inventory-import feature (Phase 24 Part B).
///
/// Maps the backend `/shopkeeper/shops/{id}/inventory-imports` contract:
/// upload → preview (row-level validation) → confirm → report.
library;

/// Canonical import-job statuses, mirrored from the backend
/// `ImportJobStatus` enum (`backend/app/models/inventory_import.py`).
///
/// The API is the single source of truth: the client never invents a status the
/// backend cannot return. [label] is the only place a raw status is turned into
/// shopkeeper-facing copy, so every surface words a state identically.
abstract final class ImportJobStatusValue {
  /// Parse/validation in flight.
  static const validating = 'VALIDATING';

  /// Preview ready — uploaded, waiting for the shopkeeper to confirm.
  static const awaitingConfirmation = 'AWAITING_CONFIRMATION';

  /// Handed to the background worker (large import).
  static const queued = 'QUEUED';

  /// Worker applying rows.
  static const processing = 'PROCESSING';

  /// Every valid row applied.
  static const completed = 'COMPLETED';

  /// Some rows failed — retry possible.
  static const partial = 'PARTIAL';

  /// File-level failure (unreadable / invalid workbook).
  static const failed = 'FAILED';

  /// Legacy alias emitted by older staged previews; the backend now sends
  /// [validating] / [awaitingConfirmation] instead.
  static const validated = 'VALIDATED';

  /// True while a job is still travelling toward a terminal outcome.
  static bool isInFlight(String status) =>
      status == validating ||
      status == awaitingConfirmation ||
      status == queued ||
      status == processing;

  /// True once rows have been applied, which is when the job's
  /// `processed_rows` / `failed_rows` counters become meaningful.
  static bool hasOutcome(String status) =>
      status == queued ||
      status == processing ||
      status == completed ||
      status == partial;

  /// Shopkeeper-facing label. An unrecognised server value degrades to
  /// humanised raw text rather than throwing, so a future backend status still
  /// renders.
  static String label(String status) => switch (status) {
    validating || validated => 'Validating',
    awaitingConfirmation => 'Uploaded',
    queued || processing => 'Processing',
    completed => 'Completed',
    partial => 'Partial Success',
    failed => 'Failed',
    _ => _humanize(status),
  };

  static String _humanize(String status) {
    final words = status.replaceAll('_', ' ').trim().toLowerCase();
    if (words.isEmpty) return 'Unknown';
    return words[0].toUpperCase() + words.substring(1);
  }
}

/// One staged import job (upload preview or a listed past job).
class ImportJob {
  const ImportJob({
    required this.id,
    required this.filename,
    required this.status,
    required this.totalRows,
    required this.validRows,
    required this.errorRows,
    this.processedRows = 0,
    this.failedRows = 0,
    this.createdAt,
    this.startedAt,
    this.completedAt,
  });

  final int id;
  final String filename;

  /// A status from [ImportJobStatusValue] (server value, never a client enum).
  final String status;
  final int totalRows;
  final int validRows;
  final int errorRows;

  /// Rows written to inventory — 0 until the job has actually been applied.
  final int processedRows;

  /// Rows that failed while being applied — 0 until the job was applied.
  final int failedRows;

  /// Upload instant (backend `created_at`), always populated.
  final DateTime? createdAt;

  /// When row processing began — null for a staged, unconfirmed upload.
  final DateTime? startedAt;

  /// When the job reached a terminal status.
  final DateTime? completedAt;

  bool get hasErrors => errorRows > 0;
  bool get isConfirmed =>
      status == ImportJobStatusValue.completed ||
      status == ImportJobStatusValue.processing ||
      status == ImportJobStatusValue.partial;

  /// Shopkeeper-facing status copy.
  String get statusLabel => ImportJobStatusValue.label(status);

  /// Best available timestamp for the history list. `started_at` is null on an
  /// unconfirmed upload, so `created_at` is the honest fallback.
  DateTime? get importDate => createdAt ?? startedAt ?? completedAt;

  /// Whether rows were applied, in which case [processedRows] / [failedRows]
  /// describe the outcome; otherwise the validation counters do.
  bool get hasProcessingOutcome => ImportJobStatusValue.hasOutcome(status);

  /// "Success" column — rows applied when the job ran, else rows that passed
  /// validation and are ready to apply.
  int get successRows => hasProcessingOutcome ? processedRows : validRows;

  /// "Failed" column — rows that failed while applying, else validation errors.
  int get failedRowCount => hasProcessingOutcome ? failedRows : errorRows;

  factory ImportJob.fromJson(Map<String, dynamic> json) => ImportJob(
    id: (json['id'] as num?)?.toInt() ?? 0,
    filename: json['filename'] as String? ?? '',
    status: json['status'] as String? ?? ImportJobStatusValue.validating,
    totalRows: (json['total_rows'] as num?)?.toInt() ?? 0,
    validRows: (json['valid_rows'] as num?)?.toInt() ?? 0,
    errorRows: (json['error_rows'] as num?)?.toInt() ?? 0,
    processedRows: (json['processed_rows'] as num?)?.toInt() ?? 0,
    failedRows: (json['failed_rows'] as num?)?.toInt() ?? 0,
    createdAt: _parseTimestamp(json['created_at']),
    startedAt: _parseTimestamp(json['started_at']),
    completedAt: _parseTimestamp(json['completed_at']),
  );
}

/// ISO-8601 → local [DateTime]; a missing or malformed value yields null
/// instead of throwing (history must render even with a partial payload).
DateTime? _parseTimestamp(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toLocal();
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
    this.jobId,
  });

  final int processed;
  final int failed;

  /// Large imports are queued for background processing.
  final bool queued;

  /// Backend job id — lets the result screen open this job's row-level report.
  /// Null when the payload omitted it.
  final int? jobId;

  factory ImportConfirmResult.fromJson(Map<String, dynamic> json) =>
      ImportConfirmResult(
        processed:
            (json['processed'] as num?)?.toInt() ??
            (json['processed_rows'] as num?)?.toInt() ??
            0,
        failed: (json['failed'] as num?)?.toInt() ?? 0,
        queued: json['queued'] as bool? ?? false,
        jobId: (json['id'] as num?)?.toInt(),
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
