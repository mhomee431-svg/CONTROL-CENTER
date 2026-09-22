/// A support ticket filed from the app and tracked by the backend.
///
/// Mirrors what `GET/POST /api/v1/shopkeeper/support/tickets` returns. Every
/// field is read straight from the response — in particular [status], which is
/// the backend's own `complaint_status` value, never a locally assumed
/// progression. A ticket an agent resolves immediately must render as
/// *Resolved*, not as "in progress".
library;

/// Display metadata for one backend status value.
///
/// The backend sends both the raw `status` and its `status_label`; the label is
/// what the shopkeeper reads, while this type supplies the value the app
/// switches on for the chip colour and icon.
enum TicketStatus {
  open('OPEN'),
  inProgress('IN_PROGRESS'),
  resolved('RESOLVED'),
  closed('CLOSED'),
  rejected('REJECTED');

  const TicketStatus(this.code);

  /// Raw value stored by the backend (`complaint_status`).
  final String code;

  /// Maps a backend status onto the app's vocabulary.
  ///
  /// An unrecognised value maps to `null` rather than guessing: a status this
  /// build does not know must not be shown as "Submitted" (that would be a lie
  /// about the ticket's state). The card then falls back to the label the
  /// backend sent, which is always authoritative.
  static TicketStatus? fromCode(String? code) {
    final wanted = (code ?? '').trim().toUpperCase();
    for (final status in values) {
      if (status.code == wanted) return status;
    }
    return null;
  }

  /// True while support is still working on the ticket.
  bool get isActive =>
      this == TicketStatus.open || this == TicketStatus.inProgress;

  /// True once the ticket is done — resolved, closed or not accepted.
  bool get isFinished => !isActive;
}


/// One tracked support ticket.
class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.reference,
    required this.subject,
    required this.description,
    required this.category,
    required this.statusCode,
    required this.statusLabel,
    this.categoryLabel,
    this.priority,
    this.shopName,
    this.attachment,
    this.resolutionNotes,
    this.createdAt,
    this.resolvedAt,
  });

  /// Server id — the value `GET .../tickets/{id}` takes.
  final int id;

  /// Short quotable number (`HL-42`), shown in the confirmation and the list.
  final String reference;

  /// One-line title derived server-side from the report.
  final String subject;

  /// What the shopkeeper wrote, including the steps and client context the
  /// backend appended for triage.
  final String description;

  /// Backend category code (`APP_*`).
  final String category;

  /// Human category name supplied by the backend (null if this build predates
  /// a category the server added — the code is then shown instead).
  final String? categoryLabel;

  /// Raw backend status value.
  final String statusCode;

  /// Wording supplied by the backend for [statusCode].
  final String statusLabel;

  /// LOW / MEDIUM / HIGH / URGENT as stored by the backend.
  final String? priority;

  /// Shop the ticket was filed against, when one was attached.
  final String? shopName;

  /// Optional screenshot attached as evidence (null when none was sent).
  final TicketAttachment? attachment;

  /// Support's explanation — present once the ticket is resolved or closed.
  final String? resolutionNotes;

  final DateTime? createdAt;
  final DateTime? resolvedAt;

  /// The app's switchable status, or null when the backend reports one this
  /// build does not recognise (see [TicketStatus.fromCode]).
  TicketStatus? get status => TicketStatus.fromCode(statusCode);

  /// True when support has answered (notes are only ever set on resolution).
  bool get hasResolution => resolutionNotes?.trim().isNotEmpty ?? false;

  /// True when a screenshot was filed with this report.
  bool get hasAttachment => attachment != null;

  /// Usable by the UI only when it carries an id, a status and a subject.
  bool get isValid => id > 0 && statusCode.isNotEmpty && subject.trim().isNotEmpty;

  static SupportTicket fromJson(Map<String, dynamic> json) => SupportTicket(
    id: (json['id'] as num?)?.toInt() ?? 0,
    reference: _text(json['reference']) ?? '',
    subject: _text(json['subject']) ?? '',
    description: _text(json['description']) ?? '',
    category: _text(json['category']) ?? '',
    categoryLabel: _text(json['category_label']),
    statusCode: _text(json['status']) ?? '',
    statusLabel: _text(json['status_label']) ?? _text(json['status']) ?? '',
    priority: _text(json['priority']),
    shopName: _text(json['shop_name']),
    attachment: TicketAttachment.fromJson(json['attachment']),
    resolutionNotes: _text(json['resolution_notes']),
    createdAt: _date(json['created_at']),
    resolvedAt: _date(json['resolved_at']),
  );

  /// Parses the `{tickets: [...]}` envelope (or a bare list).
  ///
  /// Rows the app cannot identify or whose state it cannot read are skipped: a
  /// ticket that cannot be opened must not be listed as if it were tracked.
  static List<SupportTicket> listFrom(Object? data) {
    final raw = data is Map ? data['tickets'] : data;
    if (raw is! List) return const [];
    final tickets = <SupportTicket>[];
    for (final row in raw) {
      if (row is! Map) continue;
      final ticket = SupportTicket.fromJson(
        row.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (ticket.isValid) tickets.add(ticket);
    }
    return tickets;
  }

  /// Reads the server's `total` out of a tickets response.
  ///
  /// Falls back to the number of rows in THIS response, which keeps the list
  /// from claiming a further page the server never announced.
  ///
  /// The count is taken from the raw payload rather than from [listFrom],
  /// because a row this build cannot parse is still a row the server holds —
  /// deriving "total" from the parsed rows would make an unreadable ticket look
  /// like the end of the list.
  static int totalFrom(Object? data) {
    final rows = data is Map ? data['tickets'] : data;
    final rawCount = rows is List ? rows.length : 0;
    final total = data is Map ? (data['total'] as num?)?.toInt() : null;
    return total ?? rawCount;
  }

  @override
  bool operator ==(Object other) =>
      other is SupportTicket &&
      other.id == id &&
      other.reference == reference &&
      other.subject == subject &&
      other.description == description &&
      other.category == category &&
      other.statusCode == statusCode &&
      other.statusLabel == statusLabel &&
      other.priority == priority &&
      other.shopName == shopName &&
      other.attachment == attachment &&
      other.resolutionNotes == resolutionNotes &&
      other.createdAt == createdAt &&
      other.resolvedAt == resolvedAt;

  @override
  int get hashCode => Object.hash(
    id,
    reference,
    subject,
    description,
    category,
    statusCode,
    statusLabel,
    priority,
    shopName,
    attachment,
    resolutionNotes,
    createdAt,
    resolvedAt,
  );
}


/// How many tickets one request asks for.
///
/// The tickets endpoint accepts `limit` 1…200; 20 keeps a page small enough to
/// render instantly and large enough that paging is rare for a real support
/// history.
const int supportTicketsPageSize = 20;

/// One page of the tickets endpoint, plus the server's total for the account.
///
/// The total is what makes "Load more" honest: it tells the list whether the
/// server holds rows it has not fetched yet, instead of inferring the end of
/// the list from a short page.
class SupportTicketsPage {
  const SupportTicketsPage({required this.tickets, required this.total});

  /// The rows in THIS page, newest first.
  final List<SupportTicket> tickets;

  /// How many tickets the signed-in account has in total (all pages).
  final int total;

  /// True when the server holds rows this page does not carry.
  bool get hasMore => tickets.length < total;

  /// Empty page — used when a response carried no rows at all.
  static const empty = SupportTicketsPage(tickets: [], total: 0);

  /// Parses a `{tickets: [...], total: n}` (or bare-list) response.
  factory SupportTicketsPage.fromData(Object? data) => SupportTicketsPage(
        tickets: SupportTicket.listFrom(data),
        total: SupportTicket.totalFrom(data),
      );
}


/// A screenshot attached to a ticket as evidence.
///
/// Mirrors the backend's `attachment` object: the stored media key, the
/// short-lived read URL minted for each response, and the metadata the storage
/// layer reported for the object. Everything is read from the response — the
/// app never assumes a filename or a size of its own.
class TicketAttachment {
  const TicketAttachment({
    required this.key,
    this.url,
    this.filename,
    this.contentType,
    this.sizeBytes,
  });

  /// Server-minted media key (`support/{user_id}/...`).
  final String key;

  /// Short-lived presigned read URL. It EXPIRES — re-open the ticket for a
  /// fresh one rather than caching this value.
  final String? url;

  /// Readable name derived from the stored object.
  final String? filename;

  /// Content type the storage layer reported for the object.
  final String? contentType;

  /// Size the storage layer reported for the object.
  final int? sizeBytes;

  /// True when the object is an image this app can render inline.
  bool get isImage => (contentType ?? '').toLowerCase().startsWith('image/');

  /// True when there is an image AND a URL to load it from.
  bool get isViewable => isImage && (url?.trim().isNotEmpty ?? false);

  /// Human-readable size (`1.2 MB`), or null when the backend sent none.
  String? get sizeLabel {
    final bytes = sizeBytes;
    if (bytes == null || bytes <= 0) return null;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Parses the backend's `attachment` object; null when it sent none.
  ///
  /// An object without a key is treated as no attachment: a keyless row could
  /// never be fetched or displayed, so showing it would misrepresent the ticket.
  static TicketAttachment? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.map((key, value) => MapEntry(key.toString(), value));
    final key = _text(map['key']);
    if (key == null) return null;
    return TicketAttachment(
      key: key,
      url: _text(map['url']),
      filename: _text(map['filename']),
      contentType: _text(map['content_type']),
      sizeBytes: (map['size_bytes'] as num?)?.toInt(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TicketAttachment &&
      other.key == key &&
      other.url == url &&
      other.filename == filename &&
      other.contentType == contentType &&
      other.sizeBytes == sizeBytes;

  @override
  int get hashCode => Object.hash(key, url, filename, contentType, sizeBytes);
}


/// Trimmed string, or null when absent/blank.
///
/// Top-level (not a class member) because both [SupportTicket] and
/// [TicketAttachment] parse the same wire shapes.
String? _text(Object? raw) {
  if (raw == null) return null;
  final value = raw.toString().trim();
  return value.isEmpty ? null : value;
}

/// Parsed timestamp, or null when absent/unparseable.
DateTime? _date(Object? raw) {
  if (raw is DateTime) return raw;
  if (raw == null) return null;
  final value = raw.toString().trim();
  if (value.isEmpty) return null;
  return DateTime.tryParse(value);
}

