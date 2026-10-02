/// Human-facing "when was this actually fetched" wording.
///
/// ── Why this is not `formatFreshnessText` ──────────────────────────────────
/// `formatFreshnessText` (in the search feature) answers a different question:
/// "how old is this *inventory reading*?" and returns things like
/// "Updated 5 min ago" or the alarming word "Stale". It is also free to
/// collapse anything older than a day into a single label, because for stock
/// levels the useful thing to know is simply "do not trust this".
///
/// Cached content needs different wording, and the difference is the whole
/// point of the offline experience:
///
///  * the spec mandates the literal prefix **"Last updated…"**, so a customer
///    can see at a glance that what they are reading is a snapshot;
///  * precision matters — collapsing "2 days ago" into "Stale" would hide how
///    old the data really is, and that age is what lets a customer decide
///    whether to trust a price;
///  * an unknown timestamp must say so rather than implying recency.
library;

/// Formats a cached-data timestamp as `Last updated <when>`.
///
/// Returns a labelled "unknown" rather than omitting the sentence when
/// [lastUpdated] is null: a bare absence would read as "fresh", which is the
/// exact confusion this function exists to prevent.
///
/// [now] is injectable so the output is deterministic under test.
String formatLastUpdated(DateTime? lastUpdated, {DateTime? now}) {
  if (lastUpdated == null) return 'Last updated at an unknown time';

  final reference = now ?? DateTime.now();
  final age = reference.difference(lastUpdated);

  // Clock skew (device ahead of server) genuinely means the age is unknown.
  // Rounding that to "just now" would be a lie in the customer's favour.
  if (age.isNegative) return 'Last updated at an unknown time';

  if (age.inMinutes < 1) return 'Last updated just now';
  if (age.inMinutes < 60) return 'Last updated ${age.inMinutes} min ago';
  if (age.inHours < 24) {
    final hours = age.inHours;
    return 'Last updated $hours ${hours == 1 ? 'hour' : 'hours'} ago';
  }

  final days = age.inDays;
  if (days == 1) return 'Last updated yesterday';
  if (days < 7) return 'Last updated $days days ago';

  final weeks = days ~/ 7;
  if (weeks < 5) {
    return 'Last updated $weeks ${weeks == 1 ? 'week' : 'weeks'} ago';
  }

  // Beyond a month the exact day stops being useful, but the month and year
  // keep the customer oriented without pretending to minute-level precision.
  final months = (days / 30).floor();
  if (months < 12) {
    return 'Last updated $months ${months == 1 ? 'month' : 'months'} ago';
  }
  final years = (days / 365).floor();
  return 'Last updated $years ${years == 1 ? 'year' : 'years'} ago';
}
