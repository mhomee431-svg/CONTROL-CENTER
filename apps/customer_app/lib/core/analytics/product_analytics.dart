import 'package:flutter/foundation.dart';

import '../security/safe_logger.dart';

/// The product events this app is allowed to record.
///
/// ## Why this is a closed set, not a `String`
/// ---------------------------------------
/// The failure mode of an event name typed as a `String` is that it never gets
/// reviewed. Someone writes `track('otp_submitted', {...})` because that is what
/// the moment felt like, it compiles, and no test fails. An `enum` makes the set
/// finite and reviewable, and makes risky names *unspellable* rather than
/// merely discouraged.
///
/// That matters most for this task's hard rule. An event called `otp_verified` or
/// `login_attempted` cannot exist here, which is the point: the rule is enforced
/// by the type, not by remembering it.
///
/// If a new event is genuinely wanted, add it to this enum in a review that also
/// asks "does this tell us something we could not infer otherwise?" — that
/// question is the whole value of the set.
enum AnalyticsEvent {
  searchStarted('search_started'),
  searchSubmitted('search_submitted'),
  resultOpened('result_opened'),
  productViewed('product_viewed'),
  shopViewed('shop_viewed'),
  directionsClicked('directions_clicked'),
  productSaved('saved_product'),
  shopSaved('saved_shop');

  const AnalyticsEvent(this.wireName);

  /// The stable identifier sent to the analytics sink.
  ///
  /// Separate from the Dart name so renaming a member cannot silently rewrite
  /// historical data.
  final String wireName;
}

/// Records product analytics, with values scrubbed before they leave the app.
///
/// ## What this deliberately does NOT do
/// ------------------------------------
/// It sends nothing anywhere. The sink is pluggable and defaults to null, so
/// shipping this adds no network traffic and no new dependency; a backend or SDK
/// is wired in by supplying [sink].
///
/// ## Why the scrubbing is not optional
/// -----------------------------------
/// [SafeLogger] redacts `key=value` pairs and 10-12 digit numbers, which covers
/// most log output. It does NOT cover a bare short numeric string — and a bare
/// 6-digit code is exactly what an OTP is.
///
/// A search query is free text the customer typed, so it can legitimately
/// contain a phone number, an email, or an OTP someone pasted in to track an
/// order. Forwarding that to an analytics sink would ship a customer's
/// credentials to a third party in a field labelled "query".
///
/// So every value is scrubbed before it is recorded, and the scrub is
/// deliberately aggressive: over-redacting a product name costs a little
/// analysis value, while under-redacting leaks a customer's OTP.
class ProductAnalytics {
  ProductAnalytics({this.sink});

  /// Where scrubbed events go. Null (the default) records nothing.
  AnalyticsSink? sink;

  /// Records [event] with already-known-safe [params].
  ///
  /// Every value passes through [scrub], so a caller cannot forward a raw secret
  /// even if they try.
  void track(AnalyticsEvent event, [Map<String, Object?> params = const {}]) {
    final scrubbed = <String, Object?>{
      for (final entry in params.entries)
        if (entry.value != null) entry.key: scrub('${entry.value}'),
    };

    final record = AnalyticsRecord(event: event, params: scrubbed);

    // Only the wire name and scrubbed values ever reach the sink. Debug-only,
    // and itself scrubbed, so the local log is not a second leak path.
    SafeLogger.debug('analytics ${event.wireName} ${scrubbed.keys.toList()}');
    sink?.record(record);
  }

  // ── Scrubbing ───────────────────────────────────────────────────────────
  //
  // Patterns are ordered most-specific-first. Order matters: a JWT contains dots
  // and base64url, a `Bearer ...` prefix contains a space, and a bare code is the
  // fallback.

  /// A JWT / long opaque token: two dots, three base64url segments.
  static final _jwt = RegExp(
    r'\b[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b',
  );

  /// An `Authorization`-style credential.
  ///
  /// Case-insensitivity is set with the [RegExp] constructor flag rather than an
  /// inline `(?i)` group, which Dart does not support and throws
  /// `FormatException` on at first use.
  static final _bearer = RegExp(
    r'\b(bearer|basic)\s+\S+',
    caseSensitive: false,
  );

  /// A digit-only run. 4-8 digits is OTP territory (Firebase SMS codes are 6);
  /// 10+ is a phone number; 12+ may be a card or account number.
  static final _digits = RegExp(r'\b\d{4,}\b');

  static final _email = RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+');

  /// Returns [value] with anything that could be a secret replaced.
  ///
  /// Public so callers can pre-scrub a value they need elsewhere, and so the
  /// rules are testable directly rather than only through [track].
  static String scrub(String value) {
    var out = value;

    out = out.replaceAll(_bearer, '[REDACTED_CREDENTIAL]');
    out = out.replaceAll(_jwt, '[REDACTED_TOKEN]');
    out = out.replaceAll(_email, '[REDACTED_EMAIL]');
    // Longest last: this also collapses a number embedded in an already
    // redacted token label, which is harmless.
    out = out.replaceAllMapped(
      _digits,
      (m) => '[REDACTED_NUMBER:${m.group(0)!.length}]',
    );

    // An explicit key=value safety net for callers passing structured text.
    // SafeLogger covers this too, but repeated here so the analytics path is
    // safe on its own terms rather than by depending on a sibling's behaviour.
    for (final key in const ['otp', 'token', 'password', 'authorization']) {
      out = out.replaceAll(
        RegExp('$key[:=]\\s*[^\\s,}\\]"]+', caseSensitive: false),
        '$key=[REDACTED]',
      );
    }

    return out;
  }
}

/// One recorded event: which it was, and its already-scrubbed parameters.
@immutable
class AnalyticsRecord {
  const AnalyticsRecord({required this.event, required this.params});

  final AnalyticsEvent event;
  final Map<String, Object?> params;

  @override
  String toString() => 'AnalyticsRecord(${event.wireName}, $params)';
}

/// Destination for scrubbed analytics.
///
/// Null by default, so the app ships with no analytics traffic. Wires to a
/// backend endpoint or an SDK without touching call sites.
abstract class AnalyticsSink {
  void record(AnalyticsRecord record);
}

/// Captures records in memory. For tests and local inspection.
class InMemoryAnalyticsSink implements AnalyticsSink {
  final List<AnalyticsRecord> records = <AnalyticsRecord>[];

  @override
  void record(AnalyticsRecord record) => records.add(record);
}
