/// Decodes a backend string into a Dart enum without ever throwing.
///
/// WHY THIS EXISTS
/// ---------------
/// `Enum.values.byName(raw)` throws [ArgumentError] on anything unrecognised.
/// That turns one new backend status value — `EXPIRED`, `PARTIALLY_SHIPPED`,
/// anything at all — into a crash on the screen that renders it, and it takes
/// down the whole list, not just the row.
///
/// The rule this enforces: **an unknown enum value is data, not an error.** It
/// maps to [unknown] so the UI can render "Unknown" and carry on. The customer
/// loses one label; they do not lose the screen.
///
/// [normalize] is the identity by default and is what makes this work for ANY
/// enum, including one this file has never heard of. A backend that switches
/// from `IN_STOCK` to `available` is a rename, not a new state, and the
/// mapping belongs with the model that owns the vocabulary — not here.
// PascalCase on purpose: this reads as a constructor-style decoder at the call
// site — `EnumCodec(raw, OrderStatus.values, OrderStatus.unknown)` — and it is
// already the established name across the model layer. Renaming to satisfy the
// lowerCamelCase lint would churn every call site for no behavioural gain.
// ignore: non_constant_identifier_names
T EnumCodec<T extends Enum>(String? raw, List<T> values, T fallback, {String Function(String)? normalize}) {
  if (raw == null) return fallback;
  final cleaned = raw.trim();
  if (cleaned.isEmpty) return fallback;

  // Matched case- and separator-insensitively.
  //
  // The wire spelling is usually the enum member name upper-cased
  // (`IN_STOCK`) while the Dart identifier is camelCase (`inStock`), so even a
  // case-insensitive `values.byName` fails on every multi-word status.
  // Comparing with separators removed makes both spellings collide on
  // `instock`, which is what they mean.
  final needle = _fold(cleaned);
  for (final value in values) {
    if (_fold(value.name) == needle) return value;
  }

  // Normalised match, for a backend that spells a state differently
  // ("available" for `inStock`).
  final transformer = normalize ?? _defaultNormalize;
  final normalized = transformer(cleaned.toLowerCase());
  if (normalized != null) {
    final target = _fold(normalized);
    for (final value in values) {
      if (_fold(value.name) == target) return value;
    }
  }

  // Unrecognised: fall back rather than throw. The raw value is preserved by
  // the caller's model so the UI can still show what the server actually said.
  return fallback;
}

/// Case- and separator-insensitive form used to compare two spellings of one
/// token. `in_stock`, `IN-STOCK` and `inStock` all fold to `instock`.
String _fold(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[\s\-_/]+'), '');

/// The shared "these all mean the same thing" cleanup applied before a
/// normalised comparison.
///
/// Separators, casing, and the common vendor synonyms are the only differences
/// seen in practice between two spellings of one state.
String? _defaultNormalize(String lower) {
  var s = lower.replaceAll(RegExp(r'[\s\-_/]+'), '');
  const synonyms = <String, String>{
    'instock': 'in_stock',
    'available': 'in_stock',
    'inst': 'in_stock',
    'outofstock': 'out_of_stock',
    'unavailable': 'out_of_stock',
    'oos': 'out_of_stock',
    'lowstock': 'low_stock',
    'limited': 'low_stock',
    'runninglow': 'low_stock',
    'recentlyupdated': 'recent',
    'fresh': 'recent',
    'stale': 'stale',
    'expired': 'expired',
  };
  return synonyms[s] ?? s;
}
