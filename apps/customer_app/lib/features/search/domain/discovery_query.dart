/// Product discovery: what did the customer actually type?
///
/// ## WHY A VOCABULARY AT ALL
///
/// Discovery is currently one opaque `String` handed to the backend, which
/// means the client cannot tell the difference between a product name, a brand,
/// a variant, a category and a barcode. The clearest symptom is a barcode typed
/// into the search box: it is a 13-digit string, so it is treated as free text
/// and the full-text index returns nothing useful, when the platform already has
/// an exact lookup route for precisely that identifier.
///
/// Naming the intent lets each kind of query be answered the way it deserves --
/// and lets the client route a barcode to the barcode endpoint at all.
///
/// ## WHY NOTHING HERE DEPENDS ON AI
///
/// This file is the core of discovery and it imports exactly one thing: the
/// barcode shape validator it reuses. The classifier is shape and lexicon rules
/// over a string; there is no model, no embedding, no optional-import escape
/// hatch. Semantic search is additive and lives in `semantic_reranker.dart`,
/// which can only ever *reorder* results that core discovery already produced.
///
/// That separation is the point: "AI is optional" is only true if the part that
/// must work without it has no way to reach for it.
library;

import 'barcode_validation.dart';

/// What kind of thing the customer is looking for.
enum DiscoveryMode {
  /// A product's name, or free text that is probably a name.
  productName,

  /// A known brand, e.g. "Dove".
  brand,

  /// A specific size/format of a product, e.g. "Dove 250ml" or "Amul 500g".
  variant,

  /// A browsing category, e.g. "Beauty & Personal Care".
  category,

  /// A retail symbology identifier, e.g. an EAN-13.
  barcode,
}

/// How sure the classifier is.
///
/// Recorded rather than collapsed into a bool so a caller can decide what to do
/// with a weak guess. A [guess] is still acted on for barcode queries -- routing
/// a mistyped barcode to the barcode route gives an honest "not found", whereas
/// falling back to a text search for 13 digits returns a confusing near-empty
/// result set -- but the UI is free to show a hint.
enum DiscoveryConfidence { certain, likely, guess, none }

/// A classified discovery query.
class DiscoveryQuery {
  /// Exactly what the customer typed, trimmed.
  final String raw;

  /// The resolved intent.
  final DiscoveryMode mode;

  /// What should be sent downstream: the barcode digits with separators
  /// stripped for a barcode query, otherwise [raw].
  final String normalized;

  final DiscoveryConfidence confidence;

  /// Human-readable justification, surfaced in logs and asserted in tests so
  /// the rule that fired cannot change silently.
  final String reason;

  const DiscoveryQuery({
    required this.raw,
    required this.mode,
    required this.normalized,
    required this.confidence,
    required this.reason,
  });

  /// True when this query must be answered by the barcode route.
  ///
  /// Deliberately true even at [DiscoveryConfidence.guess] — see the reasoning
  /// on that enum.
  bool get requiresBarcodeLookup => mode == DiscoveryMode.barcode;

  @override
  bool operator ==(Object other) =>
      other is DiscoveryQuery &&
      other.raw == raw &&
      other.mode == mode &&
      other.normalized == normalized &&
      other.confidence == confidence;

  @override
  int get hashCode => Object.hash(raw, mode, normalized, confidence);

  @override
  String toString() =>
      'DiscoveryQuery(${mode.name}, "$normalized", ${confidence.name})';
}

/// The terms discovery may recognise as brands and categories.
///
/// A plain data holder, not a service: the classifier must stay a pure function,
/// and the vocabulary must be injectable so a test can prove which rule fired
/// without depending on the real catalogue.
class DiscoveryLexicon {
  /// Known brand names, lower-cased.
  final Set<String> brands;

  /// Known category names, lower-cased.
  final Set<String> categories;

  const DiscoveryLexicon({this.brands = const {}, this.categories = const {}});

  /// True when [term] is a known brand.
  bool isBrand(String term) => brands.contains(term.toLowerCase());

  /// True when [term] is a known category.
  bool isCategory(String term) => categories.contains(term.toLowerCase());
}

/// Prefixes a customer can type to be explicit, e.g. `brand:dove`.
///
/// Explicit beats inferred in every case, which is what makes these worth
/// supporting: a customer who bothers to type `brand:` should never be
/// second-guessed by the heuristic that follows.
const Map<String, DiscoveryMode> kDiscoveryPrefixes = {
  'brand:': DiscoveryMode.brand,
  'category:': DiscoveryMode.category,
  'barcode:': DiscoveryMode.barcode,
  'variant:': DiscoveryMode.variant,
};

/// Matches a size or format token: "250ml", "1L", "2x", "500g pack".
///
/// A pattern rather than a list of units, so an unfamiliar measure is still
/// recognised.
final RegExp _variantPattern = RegExp(
  r'\b(\d+(?:\.\d+)?\s*(?:ml|l|g|kg|mg|oz|lb|cl|mm|cm|m|pack|packs|ct|count|x|xl|xxl|s|m))\b',
  caseSensitive: false,
);

String _key(String text) => text.trim().toLowerCase();

/// Classifies [raw] into a [DiscoveryQuery].
///
/// The rules run in a fixed order, and the order is the design:
///
///  1. **Explicit prefix** — the customer said what they meant; never override.
///  2. **Barcode shape** — before text matching, because a valid EAN is also a
///     perfectly valid "exact product name" string and a text search for 13
///     digits finds nothing.
///  3. **Category** — a known category name is unambiguous.
///  4. **Brand** — the whole query is a known brand.
///  5. **Variant** — a size/format token, which is what separates "Dove" from
///     "Dove 250ml". Deliberately ahead of a mid-query brand mention: the size
///     is the more specific signal, so it should narrow rather than widen.
///  6. **Brand mentioned mid-query** — "Dove shampoo", but not "Dove Beauty Bar".
///     See the rule itself for why one qualifier word is the dividing line.
///  7. **Product name** — the default. Free text is a name far more often than
///     not, so the honest answer is "unknown, treat it as a name" rather than a
///     fabricated guess.
DiscoveryQuery classifyDiscovery(
  String? raw, {
  DiscoveryLexicon lexicon = const DiscoveryLexicon(),
}) {
  final trimmed = (raw ?? '').trim();
  if (trimmed.isEmpty) {
    return const DiscoveryQuery(
      raw: '',
      mode: DiscoveryMode.productName,
      normalized: '',
      confidence: DiscoveryConfidence.none,
      reason: 'empty query',
    );
  }

  final lowered = _key(trimmed);

  // 1. Explicit prefix.
  for (final entry in kDiscoveryPrefixes.entries) {
    if (!lowered.startsWith(entry.key)) continue;
    final value = trimmed.substring(entry.key.length).trim();
    if (entry.value == DiscoveryMode.barcode) {
      return _barcodeQuery(
        trimmed,
        value.isEmpty ? trimmed : value,
        forced: true,
      );
    }
    if (value.isEmpty) break;
    return DiscoveryQuery(
      raw: trimmed,
      mode: entry.value,
      normalized: value,
      confidence: DiscoveryConfidence.certain,
      reason: 'explicit "${entry.key}" prefix',
    );
  }

  // 2. Barcode shape. Separators are tolerated because packaging prints them
  // ("8901030 891234") and customers copy what they see.
  final digits = normalizeBarcode(trimmed);
  final separatorsOnly = RegExp(r'^[0-9\s-]+$').hasMatch(trimmed);
  if (separatorsOnly && kValidBarcodeLengths.contains(digits.length)) {
    return _barcodeQuery(trimmed, digits, forced: false);
  }

  // 3. Category, then 4. brand.
  if (lexicon.isCategory(lowered)) {
    return DiscoveryQuery(
      raw: trimmed,
      mode: DiscoveryMode.category,
      normalized: trimmed,
      confidence: DiscoveryConfidence.certain,
      reason: 'exact known category',
    );
  }
  if (lexicon.isBrand(lowered)) {
    return DiscoveryQuery(
      raw: trimmed,
      mode: DiscoveryMode.brand,
      normalized: trimmed,
      confidence: DiscoveryConfidence.certain,
      reason: 'exact known brand',
    );
  }

  // 5. Variant marker. Checked BEFORE a brand mentioned mid-query because the
  // size is the more specific signal: "Dove 250ml" is a request for one variant,
  // and calling it a brand query would widen the result set instead of
  // narrowing it to the bottle the customer described.
  if (_variantPattern.hasMatch(trimmed)) {
    return DiscoveryQuery(
      raw: trimmed,
      mode: DiscoveryMode.variant,
      normalized: trimmed,
      confidence: DiscoveryConfidence.likely,
      reason: 'size or format token present',
    );
  }

  // 6. A brand mentioned inside a longer query, but only when the brand plus at
  // most ONE qualifier word makes up the query. "Dove shampoo" is brand-scoping
  // ("shampoo, from Dove"). "Dove Beauty Bar" is a product description whose
  // brand happens to be known, and narrowing that to the brand would also return
  // Dove Cream - worse than the plain text match it falls through to.
  for (final brand in lexicon.brands) {
    if (brand.isEmpty) continue;
    if (!RegExp('\\b${RegExp.escape(brand)}\\b').hasMatch(lowered)) continue;
    final qualifiers = trimmed
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty && t.toLowerCase() != brand)
        .length;
    if (qualifiers > 1) continue;
    return DiscoveryQuery(
      raw: trimmed,
      mode: DiscoveryMode.brand,
      normalized: trimmed,
      confidence: DiscoveryConfidence.likely,
      reason: 'known brand "$brand" within the query',
    );
  }

  // 7. Default.
  return DiscoveryQuery(
    raw: trimmed,
    mode: DiscoveryMode.productName,
    normalized: trimmed,
    confidence: DiscoveryConfidence.likely,
    reason: 'no stronger signal; treated as a product name',
  );
}

DiscoveryQuery _barcodeQuery(
  String raw,
  String digits, {
  required bool forced,
}) {
  final problem = validateBarcode(digits);
  if (problem == null) {
    return DiscoveryQuery(
      raw: raw,
      mode: DiscoveryMode.barcode,
      normalized: digits,
      confidence: DiscoveryConfidence.certain,
      reason: forced ? 'explicit barcode prefix' : 'valid barcode digits',
    );
  }
  // Wrong length was excluded by the caller, so this is a bad GS1 check digit
  // or a Code128 read. Either way the customer meant a barcode, so route it
  // there and let an honest "not found" answer it, rather than running a text
  // search over digits that will never match anything.
  return DiscoveryQuery(
    raw: raw,
    mode: DiscoveryMode.barcode,
    normalized: digits,
    confidence: forced
        ? DiscoveryConfidence.certain
        : DiscoveryConfidence.guess,
    reason: 'barcode-shaped input (${problem.name})',
  );
}
