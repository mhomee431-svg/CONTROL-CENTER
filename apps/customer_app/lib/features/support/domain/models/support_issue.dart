import '../../../../core/network/json_map.dart';

/// One support ticket the CUSTOMER filed, exactly as the backend reports it
/// (`GET /support/issues`).
///
/// WHY THIS EXISTS
/// ---------------
/// The customer app could FILE a report but never read one back. The intake
/// route (`POST /support/issues`) shipped and the app calls it, while the
/// history route (`GET /support/issues`) — which the backend has served from the
/// same router since intake was added — was never called by any screen. A
/// customer who reported a wrong price, was told "we have your report", and then
/// had no way to check whether anything happened had no recourse but to file the
/// same report again.
///
/// STATUS VOCABULARY BELONGS TO THE BACKEND
/// ----------------------------------------
/// [status] is the raw code the backend switches on and [statusLabel] is the
/// wording to display. Both are carried, and neither is derived, because the app
/// must never invent its own "Submitted → In progress → Resolved" progression: a
/// ticket an admin resolves directly would then be displayed as "in progress".
/// See `support_service.serialize_ticket`, which sends both for exactly this
/// reason.
///
/// Every field is read through [JsonMap], so a renamed or newly-optional field
/// degrades into a partially-populated ticket instead of a crash. The one field
/// treated as REQUIRED is the id, because the human-quotable [reference] is
/// derived from it: a row without an id is a row the customer cannot quote to
/// support, so [tryParse] rejects it rather than showing an unusable entry.
class SupportIssue {
  /// Backend primary key. The reference shown to the customer is derived from
  /// it (`HL-<id>`), never stored separately.
  final int id;

  /// Human-quotable ticket number, e.g. `HL-42`.
  final String reference;

  /// Raw category code (e.g. `CUST_WRONG_PRICE`).
  final String category;

  /// Display wording for [category], as sent by the backend.
  final String categoryLabel;

  final String subject;
  final String description;

  /// Raw status code (`OPEN` / `IN_PROGRESS` / `RESOLVED` / `CLOSED` /
  /// `REJECTED`). Empty when the backend reported none — which must render as
  /// "Unknown", not as an invented state.
  final String status;

  /// Display wording for [status]. Empty when the backend reported none.
  final String statusLabel;

  final String priority;

  /// The shop the report is ABOUT, when the customer named one. Context only:
  /// a customer does not own a shop, so this never implies authorization.
  final int? shopId;
  final String? shopName;

  /// What support did about it. Present only once the ticket is resolved.
  final String? resolutionNotes;

  final DateTime? resolvedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const SupportIssue({
    required this.id,
    required this.reference,
    this.category = '',
    this.categoryLabel = '',
    this.subject = '',
    this.description = '',
    this.status = '',
    this.statusLabel = '',
    this.priority = '',
    this.shopId,
    this.shopName,
    this.resolutionNotes,
    this.resolvedAt,
    this.createdAt,
    this.updatedAt,
  });

  /// Decodes one ticket, or returns null when the payload cannot be a ticket.
  ///
  /// Null (rather than a partially-blank row) for a payload with no usable id:
  /// see the class docs. Callers filter the result, so one malformed row cannot
  /// take down the whole list.
  static SupportIssue? tryParse(Object? raw) {
    final json = raw is JsonMap ? raw : JsonMap.tryParse(raw);
    final id = json.integer('id') ?? 0;
    if (id <= 0) return null;

    // The reference is the backend's to define. It is only recomputed when the
    // payload omitted it, so a future reference format (e.g. a per-year prefix)
    // is displayed as sent instead of being overwritten by a local guess.
    final reference = json.string('reference') ?? 'HL-$id';

    return SupportIssue(
      id: id,
      reference: reference,
      category: json.firstOf(['category', 'complaint_type']) ?? '',
      categoryLabel: json.string('category_label') ?? '',
      subject: json.string('subject') ?? '',
      description: json.string('description') ?? '',
      status: json.string('status') ?? '',
      statusLabel: json.string('status_label') ?? '',
      priority: json.string('priority') ?? '',
      shopId: json.integer('shop_id'),
      shopName: json.string('shop_name'),
      resolutionNotes: json.string('resolution_notes'),
      resolvedAt: json.dateTime('resolved_at'),
      createdAt: json.dateTime('created_at'),
      updatedAt: json.dateTime('updated_at'),
    );
  }

  /// What to show as the ticket's state.
  ///
  /// Falls back to the raw code, then to "Unknown". Never returns an empty
  /// string, so a ticket row can never render a blank where its state belongs —
  /// the customer would read a blank as "nothing is wrong".
  String get displayStatus {
    final label = statusLabel.trim();
    if (label.isNotEmpty) return label;
    final raw = status.trim();
    if (raw.isNotEmpty) return raw;
    return 'Unknown';
  }

  /// What to show as the ticket's category. Same rule as [displayStatus].
  String get displayCategory {
    final label = categoryLabel.trim();
    if (label.isNotEmpty) return label;
    final raw = category.trim();
    if (raw.isNotEmpty) return raw;
    return 'Report';
  }

  /// Whether the ticket has reached a terminal state, judged from the RAW
  /// backend codes — not from the display wording, which is presentation and
  /// may be translated or reworded.
  bool get isClosed {
    final key = status.trim().toUpperCase();
    return key == 'RESOLVED' || key == 'CLOSED' || key == 'REJECTED';
  }

  /// Whether support's answer is worth showing on the row.
  bool get hasResolution =>
      (resolutionNotes?.trim().isNotEmpty ?? false) || resolvedAt != null;
}
