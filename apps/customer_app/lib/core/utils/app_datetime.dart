/// The ONE place backend timestamps are parsed and rendered.
///
/// ## The rule this file exists to enforce
/// **A backend timestamp is an instant, not a wall-clock reading.** It is
/// always parsed to a UTC `DateTime` and converted to the device's zone exactly
/// once, at the display boundary. Nothing else in the app should call
/// `DateTime.parse`, `.toLocal()`, or `DateFormat(...).format()` directly.
///
/// ## Why it is not optional
/// `DateTime.parse('2026-01-15T10:00:00')` — no offset — returns a value Dart
/// treats as **local**. The backend emits that exact shape from its naive
/// columns (`sa.DateTime()`; 17 of them, against 393 tz-aware ones). So a UTC
/// value reached Dart already carrying the wrong zone, and the `.toLocal()`
/// that followed in the screens was a no-op that *looked* correct. For an India
/// device that is a silent 5h30m error on every order timestamp.
///
/// The policy below ([naiveTimestampsAreUtc]) makes that assumption explicit
/// and testable instead of implicit and invisible.
library;

import 'package:intl/intl.dart';

import 'relative_time.dart';

/// What an offset-less timestamp from the backend is assumed to mean.
///
/// `true` is correct for this deployment: the API persists with
/// `datetime.utcnow` / Postgres `now()` on a UTC database. Flipping it is a
/// one-line, test-visible change if the backend is ever re-pointed at a
/// non-UTC host — which is precisely why it is a named constant rather than an
/// assumption buried in a regex.
const bool naiveTimestampsAreUtc = true;

abstract final class AppDateTime {
  // Named so the wording is identical everywhere; intl's `h:mm a` already
  // renders "3:45 pm".
  static final DateFormat _dateTime = DateFormat('d MMM yyyy, h:mm a');
  static final DateFormat _date = DateFormat('d MMM yyyy');
  static final DateFormat _time = DateFormat('h:mm a');
  static final DateFormat _dateTimeShort = DateFormat('d MMM, h:mm a');

  /// Parses any timestamp the backend can emit. Returns **null** rather than
  /// throwing: a malformed timestamp must not crash a screen, and the caller's
  /// unknownText is a better outcome than a red error page.
  ///
  /// Accepts ISO-8601 with `Z`, with a numeric offset, with neither (see
  /// [naiveTimestampsAreUtc]), and epoch milliseconds as `int` or `String`.
  static DateTime? parse(Object? raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw.isUtc ? raw : raw.toUtc();
    if (raw is int) {
      // Epoch millis are always UTC by definition.
      return DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true);
    }
    if (raw is! String) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;

    final parsed = DateTime.tryParse(s);
    if (parsed == null) {
      // Some endpoints still send epoch millis as a JSON string.
      final asInt = int.tryParse(s);
      return asInt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(asInt, isUtc: true);
    }

    // `DateTime.parse` already sets isUtc when the text carried a `Z`.
    if (parsed.isUtc) return parsed;

    // A numeric offset was understood by DateTime.parse already.
    if (_offsetPattern.hasMatch(s)) return parsed.toUtc();

    // No offset at all: an assumption is unavoidable, so make it deliberate.
    return naiveTimestampsAreUtc
        ? DateTime.utc(
            parsed.year,
            parsed.month,
            parsed.day,
            parsed.hour,
            parsed.minute,
            parsed.second,
            parsed.millisecond,
            parsed.microsecond,
          )
        : parsed;
  }

  /// A trailing `Z`/`z`, or `+05:30` / `-0800` after the time part.
  static final RegExp _offsetPattern = RegExp(r'(?:Z|z|[+-]\d{2}:?\d{2})$');

  /// The ONLY place a timestamp becomes text.
  ///
  /// Converts to the device zone here, once. Callers pass whatever they parsed;
  /// they never call `.toLocal()` themselves.
  static String formatDateTime(DateTime? value) =>
      value == null ? unknownText : _dateTime.format(value.toLocal());

  static String formatDateTimeShort(DateTime? value) =>
      value == null ? unknownText : _dateTimeShort.format(value.toLocal());

  static String formatDate(DateTime? value) =>
      value == null ? unknownText : _date.format(value.toLocal());

  static String formatTime(DateTime? value) =>
      value == null ? unknownText : _time.format(value.toLocal());

  /// Convenience for JSON-shaped values: parse then display in one step.
  static String formatRaw(Object? raw) => formatDateTime(parse(raw));

  /// "2 hours ago" style. Delegates to the existing freshness wording so the
  /// app keeps one voice for recency.
  static String relative(DateTime? value, {DateTime? now}) =>
      formatLastUpdated(value, now: now);

  /// Shown whenever a timestamp is missing or unparseable.
  ///
  /// An em dash rather than an empty string: a blank slot reads as "nothing
  /// happened", whereas a dash reads as "we don't know", which is the truth.
  static const String unknownText = '—';

  /// Today / Yesterday / weekday, when that is more useful than a date.
  /// [now] is injectable so this is deterministic under test.
  static String friendlyDay(DateTime? value, {DateTime? now}) {
    if (value == null) return unknownText;
    final local = value.toLocal();
    final today = (now ?? DateTime.now()).toLocal();
    final days = DateTime(today.year, today.month, today.day)
        .difference(DateTime(local.year, local.month, local.day))
        .inDays;
    if (days == 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days > 1 && days < 7) {
      const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return names[local.weekday - 1];
    }
    return _date.format(local);
  }

  /// True when both instants fall on the same local calendar day. Used by
  /// order tracking to decide whether to repeat the date above a status line.
  static bool isSameLocalDay(DateTime a, DateTime b) {
    final x = a.toLocal();
    final y = b.toLocal();
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }
}