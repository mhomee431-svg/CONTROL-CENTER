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

/// How many import jobs one request asks for.
///
/// The list endpoint accepts `limit` 1…100; 20 covers months of routine
/// importing without paging, while keeping the first response small.
const int importJobsPageSize = 20;

/// One page of the import-jobs list, plus the server's count for the shop.
///
/// The count is the server's, so "Load more" is offered only when the backend
/// actually holds further jobs — a page that happens to end on a size boundary
/// is never mistaken for the end of the history.
class ImportJobPage {
  const ImportJobPage({required this.jobs, required this.total});

  /// The jobs in THIS page, newest first.
  final List<ImportJob> jobs;

  /// How many import jobs the shop has in total (all pages).
  final int total;

  /// True when the server holds jobs this page does not carry.
  bool get hasMore => jobs.length < total;

  factory ImportJobPage.fromJson(Map<String, dynamic> json) {
    final jobs = ((json['items'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ImportJob.fromJson)
        .toList(growable: false);
    return ImportJobPage(
      jobs: jobs,
      total: json['total'] as int? ?? jobs.length,
    );
  }
}



/// One row of the import preview (valid or error with a reason).
class ImportRow {
  const ImportRow({
    required this.rowNumber,
    required this.status,
    this.productName,
    this.errorCode,
    this.errorField,
    this.errorMessage,
  });

  final int rowNumber;

  /// VALID / ERROR.
  final String status;
  final String? productName;
  final String? errorCode;

  /// WHICH column the backend rejected — `barcode`, `price`, `mrp`, `row`, …
  ///
  /// The backend sends this as `error_field`, and spec §42 requires the error
  /// screen to name the field ("Row number / Field / Error"). It used to be
  /// dropped here, so the shopkeeper saw a bare code with no indication of
  /// which cell to go and fix.
  final String? errorField;
  final String? errorMessage;

  bool get isError => status == 'ERROR';

  /// True when this row was rejected for repeating an earlier one.
  ///
  /// The backend tags these `DUPLICATE_ROW` ("Duplicate of an earlier row in
  /// this file"), which is what makes §41's separate "Duplicate Rows" count
  /// computable — a duplicate is a different mistake from any other error, and
  /// folding it into one "Errors" total hides how much of a file is just
  /// repeated lines.
  bool get isDuplicate => errorCode == _duplicateCode;

  /// The one code meaning "this row repeats an earlier one". Named once so the
  /// count and the per-row badge cannot drift apart.
  static const String _duplicateCode = 'DUPLICATE_ROW';

  factory ImportRow.fromJson(Map<String, dynamic> json) => ImportRow(
    rowNumber: (json['row_number'] as num?)?.toInt() ?? 0,
    status: json['status'] as String? ?? 'VALID',
    productName: (json['product_name'] ?? json['name']) as String?,
    errorCode: json['error_code'] as String?,
    errorField: (json['error_field'] ?? json['field']) as String?,
    errorMessage: json['error_message'] as String?,
  );
}

/// Full preview payload for one job (meta + row-level outcomes).
class ImportPreview {
  const ImportPreview({
    required this.meta,
    this.rows = const [],
    this.isIdempotentReplay = false,
    this.columnMapping = const {},
    this.columnProposal = const [],
    this.headerRow = const [],
  });

  final ImportJob meta;
  final List<ImportRow> rows;

  /// Canonical field name → ZERO-BASED column index it was read from.
  ///
  /// The preview reports which column of the uploaded header row supplied each
  /// canonical field — this is what the Column Mapping step shows, and it is
  /// computed by the server from the actual file, never guessed on the client.
  /// A field absent from the file is absent from the map: "not in this file" is
  /// information the shopkeeper needs when every row reports a missing price.
  ///
  /// Deliberately a `Map<String, int>` and not the bare JSON object: dropping
  /// it (the earlier behaviour) left the mapping step with nothing but a
  /// hardcoded field list, so it could not tell a mapped column from a guess.
  final Map<String, int> columnMapping;

  /// One entry per column of the shopkeeper's OWN sheet, in file order.
  ///
  /// This is what the Column Mapping screen renders — "Item Name -> Product
  /// Name" — as opposed to [columnMapping], which is the same information keyed
  /// by field and therefore cannot express a column that maps to nothing.
  ///
  /// It exists because a mapping has three outcomes, not two: mapped, ambiguous
  /// (we will not guess) and unmapped (nobody claimed it). Collapsing the last
  /// two into "absent from the dict" is exactly the silence the spec forbids.
  final List<ImportColumnProposal> columnProposal;

  /// The header row exactly as uploaded, so the screen can show the shopkeeper
  /// their own spelling rather than a normalised version they cannot match to
  /// the sheet in front of them.
  final List<String> headerRow;

  /// Columns we refused to guess at, and so the shopkeeper must decide.
  List<ImportColumnProposal> get ambiguousColumns =>
      columnProposal.where((p) => p.isAmbiguous).toList(growable: false);

  /// Seed state for the Column Mapping screen: column index -> field name, or
  /// null for "this column is not imported".
  ///
  /// Built from the APPLIED mapping, so reopening the step shows what the rows
  /// are actually using rather than re-proposing suggestions the shopkeeper has
  /// already overridden.
  Map<int, String?> initialAssignment() {
    final byIndex = <int, String?>{
      for (final p in columnProposal) p.columnIndex: null,
    };
    for (final entry in columnMapping.entries) {
      if (byIndex.containsKey(entry.value)) byIndex[entry.value] = entry.key;
    }
    return byIndex;
  }

  /// True when the backend recognised this EXACT file as one it has already
  /// uploaded and returned the earlier job instead of re-parsing it.
  ///
  /// The backend deduplicates on file content
  /// (`excel_import_service.create_import` → `idempotent_replay`), which is
  /// right: re-uploading the same workbook must not double-import. But the app
  /// ignored the flag entirely, so a shopkeeper who corrected a file and
  /// re-uploaded it was silently handed the PREVIOUS job's preview — and
  /// "Apply valid rows" then applied the old staged rows. That defeats §40's
  /// "never immediately push an unreviewed file": the rows on screen were never
  /// in the file just picked. The preview now says so out loud.
  final bool isIdempotentReplay;

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

  /// Rows rejected for repeating an earlier row (spec §41's "Duplicate Rows").
  ///
  /// Reported SEPARATELY from [errorCount] rather than folded into it: a
  /// repeated line is a different mistake from a bad price, and the shopkeeper
  /// fixes them differently. Zero when the payload carries no row detail (large
  /// imports are summarised by the job counters), which is honest — the app
  /// never invents a duplicate count it was not told.
  int get duplicateCount =>
      rows.isEmpty ? 0 : rows.where((r) => r.isDuplicate).length;

  factory ImportPreview.fromJson(Map<String, dynamic> json) {
    final meta = ImportJob.fromJson(json);
    // The row array arrives under a DIFFERENT key depending on the endpoint:
    //   * POST /inventory-imports (upload)  → "preview"
    //   * GET  …/inventory-imports/{job}   → "rows"
    //   * a nested "report.rows" envelope is also accepted.
    // Only the GET shape was ever read, so on the UPLOAD path — the one the
    // shopkeeper actually lands on — `rows` came back empty, the preview screen
    // fell back to the job counters and showed "No rows found in this file".
    // That silently erased the whole per-row error surface (spec §42) and made
    // any row-derived count impossible to compute.
    final reportRows =
        ((json['report'] as Map<String, dynamic>?)?['rows']
            as List<dynamic>?) ??
        (json['rows'] as List<dynamic>?) ??
        (json['preview'] as List<dynamic>?);
    return ImportPreview(
      meta: meta,
      rows: (reportRows ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ImportRow.fromJson)
          .toList(growable: false),
      // Only ever true when the server says so; a missing key is a normal
      // first-time upload.
      isIdempotentReplay: json['idempotent_replay'] as bool? ?? false,
      // `column_mapping` arrives on upload (the endpoint that parsed the file
      // header) and is echoed by preview; either way the map is field→index.
      columnMapping: json['column_mapping'] is Map
          ? Map<String, int>.fromEntries(
              (json['column_mapping'] as Map).entries.map(
                (e) => MapEntry(
                  e.key.toString(),
                  (e.value as num?)?.toInt() ?? -1,
                ),
              ),
            )
          : const <String, int>{},
      columnProposal: switch (json['column_proposal']) {
        final List<dynamic> list => list
            .whereType<Map<dynamic, dynamic>>()
            .map((e) => ImportColumnProposal.fromJson(e.cast<String, dynamic>()))
            .toList(growable: false),
        _ => const <ImportColumnProposal>[],
      },
      headerRow: switch (json['header_row']) {
        final List<dynamic> list => list.map((e) => '$e').toList(growable: false),
        _ => const <String>[],
      },
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

/// One field of the backend import schema — what the Column Mapping step
/// renders.
///
/// Every rule shown to the shopkeeper comes from this object: the client never
/// holds a second copy of what a column must satisfy, because a rule written in
/// two places eventually disagrees with itself and the shopkeeper gets row
/// errors the screen cannot explain.
class ImportSchemaField {
  const ImportSchemaField({
    required this.name,
    required this.label,
    required this.rules,
    this.aliases = const [],
    this.isRequired = false,
    this.inSample = true,
  });

  /// Canonical snake_case key — the key `column_mapping` reports under.
  final String name;

  /// Shopkeeper-facing column header (also the sample workbook's header).
  final String label;

  /// Accepted header spellings for this field, e.g. `["stock", "quantity"]`.
  ///
  /// Rendered so a sheet whose header reads `Qty` can be corrected to the
  /// accepted spelling rather than guessed at.
  final List<String> aliases;

  /// Plain-language rules, already ordered for reading ("Price required",
  /// "Must be a number ≥ 0"). Not parsed, not re-interpreted on the client.
  final List<String> rules;

  /// Whether the file must supply this field (any one of the "at least one"
  /// identifier group satisfies the requirement instead).
  ///
  /// Named `isRequired` rather than `required` because `required` is a reserved
  /// word — the JSON key stays `required`.
  final bool isRequired;

  /// Whether the sample workbook carries this column — lets the screen point
  /// at the template instead of describing it from memory.
  final bool inSample;

  /// True when the uploaded file actually mapped this field (has a column).
  bool mappedIn(Map<String, int> columnMapping) =>
      columnMapping.containsKey(name);

  /// Display position of this field's column ("Column C"), or null when the
  /// file has no column for it.
  ///
  /// The mapping panel shows a position, not a semantic: the shopkeeper needs
  /// to know WHICH column of their sheet was read, so a mismatch with the sheet
  /// they are looking at is visible at a glance.
  String? columnLabel(Map<String, int> columnMapping) {
    final index = columnMapping[name];
    if (index == null || index < 0) return null;
    var n = index + 1;
    var letters = '';
    while (n > 0) {
      final rem = (n - 1) % 26;
      letters = String.fromCharCode(65 + rem) + letters;
      n = (n - 1) ~/ 26;
    }
    return 'Column $letters';
  }

  static List<String> _strings(dynamic value) => switch (value) {
    final List<dynamic> list => list.map((e) => '$e').toList(growable: false),
    _ => const [],
  };

  factory ImportSchemaField.fromJson(Map<String, dynamic> json) =>
      ImportSchemaField(
        name: json['name'] as String? ?? '',
        label: json['label'] as String? ?? json['name'] as String? ?? '',
        aliases: _strings(json['aliases']),
        rules: _strings(json['rules']),
        isRequired: json['required'] as bool? ?? false,
        inSample: json['in_sample'] as bool? ?? true,
      );
}

/// The full schema document served by `GET …/inventory-imports/schema`.
class ImportSchema {
  const ImportSchema({
    required this.fields,
    this.requiredAnyOf = const [],
    this.version,
  });

  /// Present in declaration order — the mapping panel lists them in this
  /// order so the panel matches the template's column order.
  final List<ImportSchemaField> fields;

  /// Fields of which at least one MUST appear in the file ("at least one of
  /// Barcode / SKU / Product Name identifies the product").
  final List<String> requiredAnyOf;

  /// Server schema version, when supplied — lets a stale screen be detected
  /// rather than silently rendering yesterday's rules.
  final String? version;

  /// Look up a field by its canonical key.
  ImportSchemaField? field(String name) {
    for (final f in fields) {
      if (f.name == name) return f;
    }
    return null;
  }

  /// The fields still needing a column, in schema order.
  List<ImportSchemaField> unmappedIn(Map<String, int> columnMapping) =>
      fields.where((f) => !f.mappedIn(columnMapping)).toList(growable: false);

  factory ImportSchema.fromJson(Map<String, dynamic> json) {
    final rawFields = switch (json['fields']) {
      final List<dynamic> list => list,
      _ => const <dynamic>[],
    };
    return ImportSchema(
      fields: rawFields
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (f) => ImportSchemaField.fromJson(f.cast<String, dynamic>()),
          )
          .toList(growable: false),
      requiredAnyOf: switch (json['required_any_of']) {
        final List<dynamic> list => list.map((e) => '$e').toList(growable: false),
        _ => const [],
      },
      version: json['version'] as String?,
    );
  }
}

/// How confident the backend is about one column of the uploaded sheet.
///
/// Three states, not two — the whole point of the Column Mapping step:
///
///  * [matched]   — exactly one field claims it; safe to apply.
///  * [ambiguous] — more than one column (or more than one field) could own it,
///                  so the server REFUSED to choose and the shopkeeper must.
///  * [unmatched] — no field claims it; the shopkeeper may map it by hand.
class ImportColumnProposal {
  const ImportColumnProposal({
    required this.columnIndex,
    required this.header,
    this.suggestedField,
    this.candidates = const [],
    this.status = 'unmatched',
    this.reason,
  });

  static const matched = 'matched';
  static const ambiguous = 'ambiguous';
  static const unmatched = 'unmatched';

  /// Two columns claim the same field — the classic "Price" + "Selling Price".
  static const reasonDuplicateColumn = 'MULTIPLE_COLUMNS_CLAIM_THIS_FIELD';

  /// The header text itself fits several fields.
  static const reasonSeveralFields = 'HEADER_MATCHES_SEVERAL_FIELDS';

  /// Zero-based position in the header row.
  final int columnIndex;

  /// The shopkeeper's own header spelling — never a normalised version.
  final String header;

  /// The field we would use automatically, or null when we refused to guess.
  final String? suggestedField;

  /// Every field this header could plausibly mean (populated when ambiguous).
  final List<String> candidates;

  /// One of [matched] / [ambiguous] / [unmatched].
  final String status;

  /// Machine reason for [ambiguous], or null.
  final String? reason;

  bool get isMatched => status == matched;
  bool get isAmbiguous => status == ambiguous;

  /// 1-based spreadsheet column letter, for the "Column C" hint.
  String get columnLetter {
    var n = columnIndex + 1;
    var letters = '';
    while (n > 0) {
      final rem = (n - 1) % 26;
      letters = String.fromCharCode(65 + rem) + letters;
      n = (n - 1) ~/ 26;
    }
    return letters;
  }

  /// Shopkeeper-facing reason. Empty string when there is nothing to explain —
  /// shown next to the dropdown, so it must say which choice is contested.
  String get ambiguityReason => switch (reason) {
    reasonDuplicateColumn =>
      'Another column could also be this field. Choose which one.',
    reasonSeveralFields => 'This heading could mean more than one field.',
    _ => '',
  };

  factory ImportColumnProposal.fromJson(Map<String, dynamic> json) =>
      ImportColumnProposal(
        columnIndex: (json['column_index'] as num?)?.toInt() ?? -1,
        header: json['header'] as String? ?? '',
        suggestedField: json['suggested_field'] as String?,
        candidates: switch (json['candidates']) {
          final List<dynamic> list => list.map((e) => '$e').toList(growable: false),
          _ => const <String>[],
        },
        status: json['status'] as String? ?? unmatched,
        reason: json['reason'] as String?,
      );
}

/// A locally-picked .xlsx workbook ready for upload.
class PickedWorkbook {
  const PickedWorkbook({required this.path, required this.name, this.sizeBytes});

  final String path;
  final String name;

  /// Size in bytes when the platform reported it, else null.
  ///
  /// Carried so the 5 MB cap can be checked BEFORE the upload rather than
  /// after it: sending a 40 MB workbook to be told it is too large wastes the
  /// shopkeeper's data and their time. Null means "unknown", and an unknown size
  /// is left to the server rather than guessed at.
  final int? sizeBytes;

  String get extension =>
      name.contains('.') ? name.split('.').last.toLowerCase() : '';
}
