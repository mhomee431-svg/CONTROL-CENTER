/// Why this file exists
/// --------------------
/// A share sheet is the one place in the app where data leaves the customer's
/// device and lands in a *third-party* app, a group chat, an email, or a
/// clipboard the customer later pastes somewhere public. There is no second
/// chance: once WhatsApp has the string, the app has no control over it.
///
/// Everything composed for a share therefore passes [assertShareIsSafe] before
/// it is handed to the platform. The rule the app commits to is narrow and
/// absolute:
///
///   **No credential and no internal identifier may appear in shareable text.**
///
/// "Shareable text" is the human-readable message the recipient reads. A deep
/// link legitimately carries a product id in its path -- that is how the link
/// resolves -- so ids are confined to [ShareContent.url] and are never
/// interpolated into prose. Credentials have no legitimate reason to appear at
/// all, in either field.
///
/// The patterns below are deliberately narrow. A scanner that flagged ordinary
/// copy ("Dove Shampoo, 4.5 stars, 128 reviews") would get switched off, and a
/// switched-off scanner is worse than none, because it looks like a safeguard.
library;

/// A piece of shareable material that must not leave the app.
class ShareLeak {
  /// Which pattern matched, e.g. `jwt`.
  final String kind;

  /// The offending fragment, truncated so this can be logged safely.
  final String excerpt;

  const ShareLeak(this.kind, this.excerpt);

  @override
  String toString() => 'ShareLeak($kind)';
}

final RegExp _jwt = RegExp(
  r'\beyJ[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]{4,}',
);

final RegExp _bearer = RegExp(r'\bBearer\s+[A-Za-z0-9._~+/=-]{8,}');

final RegExp _secretAssignment = RegExp(
  r'\b(access[_-]?token|refresh[_-]?token|session[_-]?id|auth[_-]?token|'
  r'api[_-]?key|authorization|password|otp)\b\s*[=:]\s*\S+',
  caseSensitive: false,
);

final RegExp _secretQueryParam = RegExp(
  r'[?&](token|access_token|refresh_token|key|api_key|signature|sig|auth)=',
  caseSensitive: false,
);

/// A long hex run. 32 chars is two 128-bit blocks, far past any order id,
/// postcode-plus or product code a customer would legitimately read aloud.
final RegExp _longHex = RegExp(r'\b[0-9a-fA-F]{32,}\b');

/// RFC1918 / loopback hosts. Sharing one of these publishes the company's
/// internal network topology to whoever receives the link.
final RegExp _privateHost = RegExp(
  r'\b(?:localhost|127\.0\.0\.1|0\.0\.0\.0|10\.\d{1,3}\.\d{1,3}\.\d{1,3}|'
  r'192\.168\.\d{1,3}\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3})\b',
);

/// Patterns that mean "this string carries a credential or internal detail".
///
/// `final`, not `const`: [RegExp] has no const constructor, so a const list of
/// these is impossible.
final List<({String kind, RegExp pattern})> shareLeakPatterns = [
  (kind: 'jwt', pattern: _jwt),
  (kind: 'bearer', pattern: _bearer),
  (kind: 'secret-assignment', pattern: _secretAssignment),
  (kind: 'secret-query-param', pattern: _secretQueryParam),
  (kind: 'long-hex-blob', pattern: _longHex),
  (kind: 'private-host', pattern: _privateHost),
];

/// Scans [text] for anything that must not be shared.
///
/// Returns every match rather than a bool so a caller can log *what* was found
/// in debug without logging the value itself.
List<ShareLeak> findShareLeaks(String? text) {
  if (text == null || text.isEmpty) return const [];
  final leaks = <ShareLeak>[];
  for (final entry in shareLeakPatterns) {
    for (final match in entry.pattern.allMatches(text)) {
      final matched = match.group(0) ?? '';
      if (matched.isEmpty) continue;
      leaks.add(ShareLeak(entry.kind, _excerpt(matched)));
    }
  }
  return leaks;
}

/// Truncates a matched fragment so it is safe to put in a log line.
String _excerpt(String value) =>
    value.length <= 12 ? value : '${value.substring(0, 12)}…';
