import 'package:intl/intl.dart';

/// Utilities for resilient and consistent date and time handling.
///
/// Ensures all backend UTC timestamps are safely parsed and converted to the
/// device's local timezone before comparison or display, preventing UTC/local
/// mixing bugs.
class DateTimeUtils {
  DateTimeUtils._();

  /// Safely parse an ISO-8601 string or DateTime object into a local [DateTime].
  /// Returns null if [raw] is null, empty, or unparseable.
  static DateTime? tryParseToLocal(Object? raw) {
    if (raw == null) return null;
    if (raw is DateTime) {
      return raw.isUtc ? raw.toLocal() : raw;
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      final parsed = DateTime.tryParse(trimmed);
      if (parsed == null) return null;
      return parsed.isUtc ? parsed.toLocal() : parsed;
    }
    return null;
  }

  /// Formats a [DateTime] into a friendly relative label or localized string.
  ///
  /// Relative wording always wins while the age is under a day; the
  /// calendar-day labels only take over once "N h ago" would be misleading.
  ///
  /// Examples:
  /// - Under 1 minute: "just now"
  /// - Under 60 minutes: "15 min ago"
  /// - Under 24 hours: "5 h ago"
  /// - Yesterday: "Yesterday 09:30"
  /// - Within current year: "12 Oct, 14:05"
  /// - Older: "12 Oct 2025, 14:05"
  static String formatRelativeOrLocal(
    DateTime? dateTime, {
    DateTime? referenceNow,
    String nullLabel = 'Not updated yet',
  }) {
    if (dateTime == null) return nullLabel;
    final localDt = dateTime.isUtc ? dateTime.toLocal() : dateTime;
    final now = (referenceNow ?? DateTime.now());
    final localNow = now.isUtc ? now.toLocal() : now;

    final diff = localNow.difference(localDt);
    if (diff.isNegative) {
      // Timestamp in future (clock skew) — show the absolute local time.
      return DateFormat('d MMM yyyy, HH:mm').format(localDt);
    }

    if (diff.inSeconds < 60) {
      return 'just now';
    }
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} min ago';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours} h ago';
    }

    final today = DateTime(localNow.year, localNow.month, localNow.day);
    final dtDay = DateTime(localDt.year, localDt.month, localDt.day);
    final dayDiff = today.difference(dtDay).inDays;

    // Age is already >= 24h here, so `dayDiff` is never 0: a stamp at least a
    // day old has always crossed a local midnight. Only the "Yesterday" and
    // absolute forms are reachable, which is why there is no "Today" branch —
    // anything from today is already served by the relative hours above.
    final timeStr = DateFormat('HH:mm').format(localDt);

    if (dayDiff == 1) {
      return 'Yesterday $timeStr';
    }
    if (localNow.year == localDt.year) {
      return DateFormat('d MMM, HH:mm').format(localDt);
    }
    return DateFormat('d MMM yyyy, HH:mm').format(localDt);
  }

  /// Formats a date for compact display (e.g. "12 Oct 2026").
  static String formatShortDate(DateTime? dateTime) {
    if (dateTime == null) return '—';
    final localDt = dateTime.isUtc ? dateTime.toLocal() : dateTime;
    return DateFormat('d MMM yyyy').format(localDt);
  }

  // ── Data freshness (unified across Inventory, Pricing and POS) ─────────────
  //
  // One calendar-aware age phrase so every surface answers "how old is this
  // data?" with the same vocabulary:
  //   * under 1 minute:  "Inventory updated just now"
  //   * under 60 minutes: "Inventory updated 15 min ago"
  //   * same calendar day: "Price updated today"
  //   * previous day:      "Last POS sync yesterday"
  //   * older:             "Inventory updated 12 Oct 2026"
  //   * missing timestamp: the caller's null label
  //
  // Relative wording wins while it is precise; the calendar words only take
  // over once "N min ago" would stop being useful (an hour+ age), which is why
  // there is no "N h ago" form here — an age that crosses midnight is honestly
  // "yesterday", not "26 h ago".

  /// Core freshness formatter. [prefix] is the noun phrase the surface owns
  /// (`'Inventory updated'`, `'Price updated'`, `'Last POS sync'`), so the
  /// helpers below only differ by wording.
  static String formatFreshness(
    String prefix,
    DateTime? when, {
    DateTime? referenceNow,
    String nullLabel = 'Not updated yet',
  }) {
    if (when == null) return nullLabel;
    final localDt = when.isUtc ? when.toLocal() : when;
    final now = (referenceNow ?? DateTime.now());
    final localNow = now.isUtc ? now.toLocal() : now;

    final diff = localNow.difference(localDt);
    if (diff.isNegative) {
      // Future stamp (clock skew): describe the instant, never an "ago".
      return '$prefix ${formatRelativeOrLocal(localDt, referenceNow: localNow)}';
    }
    if (diff.inMinutes < 1) return '$prefix just now';
    if (diff.inMinutes < 60) return '$prefix ${diff.inMinutes} min ago';

    // From an hour on the age is read as calendar days: anything still inside
    // today reads "today", a stamp that crossed the local midnight reads
    // "yesterday" (even if only by minutes — the calendar is what the label
    // claims), and everything older shows its date.
    final today = DateTime(localNow.year, localNow.month, localNow.day);
    final dtDay = DateTime(localDt.year, localDt.month, localDt.day);
    final dayDiff = today.difference(dtDay).inDays;
    if (dayDiff <= 0) return '$prefix today';
    if (dayDiff == 1) return '$prefix yesterday';
    return '$prefix ${formatShortDate(localDt)}';
  }

  /// "Inventory updated …" — the Inventory module's freshness voice.
  static String formatInventoryFreshness(
    DateTime? when, {
    DateTime? referenceNow,
    String nullLabel = 'Inventory not updated yet',
  }) => formatFreshness(
        'Inventory updated',
        when,
        referenceNow: referenceNow,
        nullLabel: nullLabel,
      );

  /// "Price updated …" — the Pricing module's freshness voice.
  static String formatPriceFreshness(
    DateTime? when, {
    DateTime? referenceNow,
    String nullLabel = 'Price not updated yet',
  }) => formatFreshness(
        'Price updated',
        when,
        referenceNow: referenceNow,
        nullLabel: nullLabel,
      );

  /// "Last POS sync …" — the POS module's freshness voice.
  static String formatPosSyncFreshness(
    DateTime? when, {
    DateTime? referenceNow,
    String nullLabel = 'No POS sync yet',
  }) => formatFreshness(
        'Last POS sync',
        when,
        referenceNow: referenceNow,
        nullLabel: nullLabel,
      );

  /// True when [when] is older than [threshold] (24 hours by default) — the
  /// stale indicator behind the freshness labels.
  ///
  /// A missing timestamp carries no evidence either way, so `null` is NOT
  /// stale: surfaces render the null label instead of crying wolf. Future
  /// stamps (clock skew) are not stale either.
  static bool isStale(
    DateTime? when, {
    Duration threshold = const Duration(hours: 24),
    DateTime? referenceNow,
  }) {
    if (when == null) return false;
    final localDt = when.isUtc ? when.toLocal() : when;
    final now = (referenceNow ?? DateTime.now());
    final localNow = now.isUtc ? now.toLocal() : now;
    final diff = localNow.difference(localDt);
    return !diff.isNegative && diff > threshold;
  }
}
