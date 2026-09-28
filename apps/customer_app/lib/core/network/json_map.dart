import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Typed, total accessors for one decoded JSON object.
///
/// WHY THIS EXISTS
/// ---------------
/// Repositories read fields with three different idioms, each of which fails
/// differently against a changed or incomplete API response:
///
/// ```dart
/// json['id'] as int                    // THROWS when the field is absent,
///                                       //   or when a newer API returns "42"
/// json['name'] as String? ?? ''        // THROWS when it returns 42 or a map
/// (json['price'] as num?)?.toDouble()   // silently yields null/0 for a
///                                       //   string price, hiding the problem
/// ```
///
/// A `TypeError` from any of these escapes as an opaque crash: the customer
/// sees a failure screen for what is really one renamed or newly-optional
/// field, and the fix requires a code change rather than a config change.
///
/// This class makes every read total — it returns a sensible value or `null`,
/// never throws — so a response that is missing a field, has a field of an
/// unexpected type, or carries a value this build has never heard of degrades
/// into a partially-populated model instead of a crash.
///
/// It is deliberately NOT `Map<String, dynamic>`. That type is what let raw
/// JSON reach the UI in the first place; keeping the same shape here would
/// reproduce the problem behind a nicer name.
@immutable
class JsonMap {
  final Map<String, dynamic> _raw;

  const JsonMap(this._raw);

  /// Wraps [value] if it is a JSON object, otherwise yields an EMPTY map.
  ///
  /// Returning empty rather than throwing is what lets a caller decode a field
  /// the server sent as `null`, a list, or a bare string. The resulting model
  /// is then simply empty — degraded, not crashed.
  ///
  /// A [JsonMap] is returned AS-IS rather than unwrapped and re-wrapped. That
  /// matters: `objectList` hands back `JsonMap`s, and re-wrapping one would
  /// produce an EMPTY map (a `JsonMap` is not a `Map`), silently blanking every
  /// field of a perfectly valid nested model.
  factory JsonMap.tryParse(Object? value) {
    if (value is JsonMap) return value;
    if (value is Map<String, dynamic>) return JsonMap(value);
    // A `Map<dynamic, dynamic>` shows up when JSON is decoded through a path
    // that loses the key type; normalise rather than reject.
    if (value is Map) {
      return JsonMap(value.map((k, v) => MapEntry(k.toString(), v)));
    }
    return const JsonMap({});
  }

  /// The underlying map. For forwarding to a legacy decoder only.
  Map<String, dynamic> get raw => _raw;

  bool get isEmpty => _raw.isEmpty;
  bool get isNotEmpty => _raw.isNotEmpty;

  /// Whether [key] is present AND non-null.
  bool has(String key) => _raw[key] != null;

  // ── Scalars ────────────────────────────────────────────────────────────
  /// Reads [key] as a trimmed, non-empty string, or null.
  ///
  /// Non-string values are coerced rather than discarded: an API that starts
  /// sending `"id": 42` instead of `"id": "42"` is a version change the app
  /// should ride out, not crash on.
  String? string(String key) {
    final v = _raw[key];
    if (v == null) return null;
    if (v is String) {
      final t = v.trim();
      return t.isEmpty ? null : t;
    }
    if (v is num || v is bool) return v.toString();
    return null;
  }

  /// [string], falling back to [orElse] (default `''`).
  String stringOr(String key, [String orElse = '']) => string(key) ?? orElse;

  /// Reads [key] as an int, or null.
  ///
  /// Accepts a JSON number, a numeric string, or a whole-valued double — all
  /// three are things a real backend has emitted for an id.
  int? integer(String key) {
    final v = _raw[key];
    if (v is int) return v;
    if (v is double) return v.isFinite ? v.round() : null;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  int integerOr(String key, [int orElse = 0]) => integer(key) ?? orElse;

  /// Reads [key] as a double, or null.
  ///
  /// Handles a JSON number, a numeric string, and the common backend habit of
  /// sending money as a formatted string ("1,299.00"). Separators and a
  /// currency symbol are stripped; anything still unparseable is null.
  double? decimal(String key) {
    final v = _raw[key];
    if (v is double) return v.isFinite ? v : null;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    if (v is String) {
      var cleaned = v.trim();
      if (cleaned.isEmpty) return null;
      cleaned = cleaned.replaceAll(RegExp(r'[^\d.\-]'), '');
      if (cleaned.isEmpty) return null;
      final parsed = double.tryParse(cleaned);
      return (parsed != null && parsed.isFinite) ? parsed : null;
    }
    return null;
  }

  double decimalOr(String key, [double orElse = 0]) => decimal(key) ?? orElse;

  /// Reads [key] as a bool, or null.
  ///
  /// Accepts real booleans plus the string/number spellings that appear when a
  /// query-param or spreadsheet-sourced value is echoed back. Anything else is
  /// null, which callers render as "not reported" rather than as `false`.
  ///
  /// Null rather than defaulting to `false` matters: `false` is a factual claim
  /// ("the backend said no"), and inventing it from unparseable data is how a
  /// customer gets told an item is out of stock when the server merely sent
  /// something new.
  bool? boolean(String key) {
    final v = _raw[key];
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      switch (v.trim().toLowerCase()) {
        case 'true':
        case 'yes':
        case 'y':
        case '1':
          return true;
        case 'false':
        case 'no':
        case 'n':
        case '0':
          return false;
        default:
          return null;
      }
    }
    return null;
  }

  /// [boolean], defaulting to `false` ONLY where the field is a plain flag
  /// whose absence genuinely means "no" (e.g. an "is_admin" style flag).
  bool booleanOr(String key, [bool orElse = false]) => boolean(key) ?? orElse;

  /// Reads [key] as a [DateTime], or null.
  ///
  /// Handles ISO-8601, epoch seconds, and epoch milliseconds. The latter two
  /// are told apart by magnitude, because treating seconds as milliseconds
  /// silently returns 1970 for a perfectly valid timestamp.
  DateTime? dateTime(String key) {
    final v = _raw[key];
    if (v is DateTime) return v;
    if (v is int) return _fromEpoch(v);
    if (v is double) return _fromEpoch(v.round());
    if (v is String) {
      final t = v.trim();
      if (t.isEmpty) return null;
      // A numeric string is an epoch value, NOT a date. It must be checked
      // BEFORE `DateTime.tryParse`, which happily accepts a bare number and
      // interprets it as year 1767225600 — a date ~56 million years out, which
      // then renders as a wildly wrong "last updated" value.
      if (_looksNumeric(t)) return _fromNumericString(t);
      final parsed = DateTime.tryParse(t);
      if (parsed != null) return parsed;
      return null;
    }
    return null;
  }

  /// True for a string that is entirely a number (optionally signed/decimal).
  static bool _looksNumeric(String value) =>
      RegExp(r'^-?\d+(\.\d+)?$').hasMatch(value);

  static DateTime? _fromEpoch(int value) {
    if (value <= 0) return null;
    // ~1e11 ms is the year 5138, so anything below that cannot be milliseconds
    // and must be seconds.
    return value < 100000000000
        ? DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true)
        : DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }

  /// [dateTime], but also interpreting a numeric string as an epoch value.
  ///
  /// A timestamp sent as `"1767225600"` rather than a JSON number is a
  /// plausible API change, and `DateTime.tryParse` does not handle it.
  static DateTime? _fromNumericString(String value) {
    final asInt = int.tryParse(value);
    if (asInt != null) return _fromEpoch(asInt);
    final asDouble = double.tryParse(value);
    if (asDouble != null) return _fromEpoch(asDouble.round());
    return null;
  }

  // ── Structures ──────────────────────────────────────────────────────────
  /// Reads [key] as a nested object, or an EMPTY one.
  ///
  /// Empty rather than null so a caller can keep reading fields without
  /// branching on presence.
  JsonMap object(String key) => JsonMap.tryParse(_raw[key]);

  /// Reads [key] as a list, or an empty one.
  ///
  /// Tolerates a single object where a list was expected — some endpoints
  /// collapse a one-element collection to the bare object.
  List<dynamic> list(String key) {
    final v = _raw[key];
    if (v is List) return v;
    if (v == null) return const [];
    if (v is Map || v is String) return [v];
    return const [];
  }

  /// Reads [key] as a list of objects, dropping entries that are not objects.
  ///
  /// Dropping rather than failing is deliberate: one malformed row in a list of
  /// 20 shops should cost the customer that one row, not the whole screen.
  List<JsonMap> objectList(String key) => list(key)
      .whereType<Map<dynamic, dynamic>>()
      .map(JsonMap.tryParse)
      .toList(growable: false);

  /// Reads [key] as a list of strings, dropping entries that are not strings.
  List<String> stringList(String key) => list(key)
      .map((e) {
        if (e is String) {
          final t = e.trim();
          return t.isEmpty ? null : t;
        }
        if (e is num || e is bool) return e.toString();
        return null;
      })
      .whereType<String>()
      .toList(growable: false);

  /// Reads [key] as a `Map<String, String>`, skipping non-scalar entries.
  Map<String, String> stringMap(String key) {
    final v = _raw[key];
    if (v is! Map) return const {};
    final out = <String, String>{};
    v.forEach((k, value) {
      if (value == null) return;
      if (value is Map || value is List) return;
      out[k.toString()] = value.toString();
    });
    return out;
  }

  /// Reads [key] as a JSON-encoded string and decodes it.
  ///
  /// Several endpoints store structured data in a TEXT column containing JSON
  /// (`attributes_json`, `metadata_json`). Malformed content yields an empty
  /// map rather than an exception, so one bad row cannot break its parent.
  JsonMap nestedJson(String key) {
    // If the value is already an object there is nothing to decode — a newer
    // API may have stopped double-encoding it. This must be checked against the
    // RAW value, because `string(key)` would stringify a map to
    // `{color: red}` and the `startsWith('{')` test below would then try to
    // jsonDecode that, which fails.
    final rawValue = _raw[key];
    if (rawValue is Map) return JsonMap.tryParse(rawValue);

    final rawString = string(key);
    if (rawString == null) return const JsonMap({});
    if (!rawString.startsWith('{')) return const JsonMap({});
    try {
      return JsonMap.tryParse(jsonDecode(rawString));
    } catch (_) {
      return const JsonMap({});
    }
  }

  // ── Version-tolerant lookups ────────────────────────────────────────────
  /// Reads the first key in [keys] that carries a value, as a string.
  ///
  /// This is the mechanism for surviving a RENAME without shipping a fix. When
  /// the backend moves `stock_status` to `availability`, the old name keeps
  /// working for one release and the new one is picked up as soon as it
  /// appears:
  ///
  /// ```dart
  /// final status = json.firstOf(['availability', 'stock_status']);
  /// ```
  ///
  /// Order matters and should be NEWEST-FIRST, so the new name wins the moment
  /// both are sent. A key that is present but `null` counts as absent, because
  /// a null is a missing value however it happens to be spelled.
  String? firstOf(List<String> keys) {
    for (final key in keys) {
      final v = string(key);
      if (v != null) return v;
    }
    return null;
  }

  /// First present key coerced to a double, or null.
  double? firstDecimalOf(List<String> keys) {
    for (final key in keys) {
      final v = decimal(key);
      if (v != null) return v;
    }
    return null;
  }

  /// First present key coerced to a bool, or null.
  ///
  /// Distinguishes "key absent" from "key present but unreadable": a bool the
  /// server genuinely reported as `false` is returned, while a value this build
  /// cannot interpret falls through to the next alias and finally to null.
  bool? firstBooleanOf(List<String> keys) {
    for (final key in keys) {
      if (!_raw.containsKey(key)) continue;
      final v = boolean(key);
      if (v != null) return v;
    }
    return null;
  }

  /// First present key parsed as a [DateTime], or null.
  DateTime? firstDateTimeOf(List<String> keys) {
    for (final key in keys) {
      if (!_raw.containsKey(key)) continue;
      final v = dateTime(key);
      if (v != null) return v;
    }
    return null;
  }

  /// First present key read as a nested object, or an empty one.
  JsonMap firstObjectOf(List<String> keys) {
    for (final key in keys) {
      if (!_raw.containsKey(key)) continue;
      final v = _raw[key];
      if (v is Map) return JsonMap.tryParse(v);
    }
    return const JsonMap({});
  }

  /// Every key the server sent that this build does not recognise.
  ///
  /// Surfaced in debug builds so an unrecognised field is VISIBLE during
  /// development rather than silently dropped. This is how a rename gets caught
  /// before it reaches customers, and it is the difference between a new API
  /// version showing up as a log line and showing up as a mystery.
  Set<String> unknownKeys(Iterable<String> known) {
    if (!kDebugMode) return const {};
    final knownSet = known.toSet();
    return _raw.keys.where((k) => !knownSet.contains(k)).toSet();
  }

  @override
  String toString() => 'JsonMap(${_raw.length} keys)';
}
