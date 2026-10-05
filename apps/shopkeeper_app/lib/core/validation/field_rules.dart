/// UI-level validation for the two surfaces `ProductFormRules` does not cover.
///
/// The app already has a well-built rule set for product forms
/// (`features/products/domain/product_form_rules.dart`): it returns CODES rather
/// than sentences, so the wording stays in `app_en.arb`, and it mirrors the
/// backend's schema exactly. This module deliberately does NOT restate price,
/// MRP, quantity or barcode rules — a second copy of those numbers is how a
/// client ends up validating something the server never checks, and the
/// existing rules already own them.
///
/// What is genuinely missing lives here:
///
///  * [FieldLimits] — the IMPORT's text maxima, which are column widths rather
///    than pydantic schema bounds, and which the server now publishes through
///    the import schema so the app does not hardcode them either.
///  * [importWorkbook] — file type and size, checked before a byte is uploaded.
///  * [stockDelta] — a stock ADJUSTMENT (whole, non-zero, sign meaningful),
///    which is a different question from a product's stock value.
library;

/// Maximum text length per import column, mirroring the backend's column widths
/// (see `backend/app/core/field_limits.py`).
///
/// Used until the server's schema arrives; replaced by [FieldLimits.fromSchema]
/// as soon as it does, so the two cannot disagree for long.
class FieldLimits {
  const FieldLimits(this.values);

  static const productName = 'product_name';
  static const variant = 'variant';
  static const sku = 'sku';
  static const barcode = 'barcode';
  static const brand = 'brand';
  static const category = 'category';
  static const subcategory = 'subcategory';

  /// Mirrors `FIELD_LIMITS` in the backend, to the character.
  static const defaults = FieldLimits({
    productName: 255,
    variant: 255,
    sku: 100,
    barcode: 100,
    brand: 120,
    category: 100,
    subcategory: 100,
  });

  final Map<String, int> values;

  /// The server's file cap. 5 MB, matching `MAX_FILE_SIZE_BYTES`.
  static const maxFileBytes = 5 * 1024 * 1024;

  /// The only extension the importer accepts.
  static const allowedExtensions = ['.xlsx'];

  /// Adopt the server's limits, keeping the defaults for any field it did not
  /// mention (a newer server may know about fields this build does not).
  factory FieldLimits.fromSchema(Map<String, dynamic>? limits) {
    if (limits == null || limits.isEmpty) return defaults;
    final merged = {...defaults.values};
    for (final entry in limits.entries) {
      final v = entry.value;
      if (v is num && v > 0) merged[entry.key] = v.toInt();
    }
    return FieldLimits(merged);
  }

  int of(String field) => values[field] ?? 255;
}

/// A value longer than its column width, or null.
///
/// Measured on the trimmed value, like the backend: Excel pads cells and the
/// padded characters are never stored.
String? importFieldTooLong(
  String? value,
  String field, [
  FieldLimits? limits,
]) {
  final max = (limits ?? FieldLimits.defaults).of(field);
  final actual = (value ?? '').trim().length;
  if (actual <= max) return null;
  return '$actual characters; the maximum is $max';
}

/// A stock adjustment: whole, non-zero, and negative is fine (it removes
/// stock). Blank is not — "no change" is not what this action means.
///
/// Deliberately NOT [ProductFormRules.quantity]: that judges a product's stock
/// value (absolute, `>= 0`), while an adjustment is a signed delta that may not
/// be zero. Reusing one rule for both would make either the sheet or the
/// adjustment wrong.
///
/// These messages are plain English, matching the wording this screen already
/// used inline. They are NOT part of the l10n vocabulary on purpose: routing
/// them through `AppText` would need generated localisation keys for a rule set
/// that has no counterpart in `ProductFormRules`.
String? stockDelta(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return 'Enter a quantity change';
  final value = num.tryParse(text);
  if (value == null || value != value.roundToDouble()) {
    return 'Enter a whole number';
  }
  if (value == 0) return 'Enter a non-zero quantity change';
  return null;
}

/// Reject a workbook the backend would refuse — before a single byte is sent.
///
/// Checking here turns a multi-megabyte upload that ends in a rejection into an
/// instant, specific message. The size check is skipped when the size is
/// unknown: the picker does not always report it, and guessing is worse than
/// letting the server be the authority.
String? importWorkbook(
  String name, {
  int? bytes,
  int maxBytes = FieldLimits.maxFileBytes,
}) {
  if (name.trim().isEmpty) return 'Choose a workbook to upload';
  final lower = name.toLowerCase();
  final allowed = FieldLimits.allowedExtensions;
  if (!allowed.any((ext) => lower.endsWith(ext))) {
    return 'Only ${allowed.join(' / ')} files are supported';
  }
  if (bytes != null && bytes > maxBytes) {
    final mb = (bytes / (1024 * 1024)).toStringAsFixed(1);
    return 'That file is $mb MB; the maximum is '
        '${(maxBytes / (1024 * 1024)).round()} MB';
  }
  return null;
}


/// Maximum text length per canonical field, mirroring the backend's column
/// widths (see `backend/app/core/field_limits.py`).
/// An offer must end after it starts.
///
/// The same rule as the `ck_offers_end_after_start` CHECK, applied here so the
/// Save button is disabled rather than the server bouncing a red error back.
///
/// Nothing else checks this client-side: `ProductFormRules` has no date rules
/// at all, so this is the only copy of the rule on the client.
String? offerDateRange(DateTime? start, DateTime? end) {
  if (start == null) return 'Choose a start date';
  if (end == null) return 'Choose an end date';
  if (!end.isAfter(start)) return 'End date must be after the start date';
  return null;
}

/// A date that is not in the past, compared by DAY.
///
/// Time-of-day is deliberately ignored: an offer that starts today is valid
/// even at 11pm, and a comparison that included the hour would fail something
/// the shopkeeper reads as obviously fine.
String? notInThePast(DateTime? date, String label, {DateTime? now}) {
  if (date == null) return null;
  final reference = now ?? DateTime.now();
  final today = DateTime(reference.year, reference.month, reference.day);
  final d = DateTime(date.year, date.month, date.day);
  if (d.isBefore(today)) return '\$label cannot be in the past';
  return null;
}
