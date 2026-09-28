/// Raised when a response arrived intact but its SHAPE is unusable.
///
/// WHY A DEDICATED TYPE
/// --------------------
/// A malformed or unexpectedly-shaped payload is a different failure from a
/// network or server error:
///
///  * it needs a different log line (it usually means a client/server contract
///    mismatch, and the endpoint name is the single most useful fact to have);
///  * it must NOT be cached, because a payload we could not parse has no
///    trustworthy subset to fall back on;
///  * retrying it unchanged will fail identically, so it must not be presented
///    as a transient error the customer can simply try again.
///
/// Throwing a bare `Exception` (as this code used to) lost the endpoint and made
/// all three of those distinctions impossible.
class ApiPayloadException implements Exception {
  /// The logical payload that failed to decode, e.g. `product_details`.
  ///
  /// Not a path: it identifies the SHAPE that broke, which is what a reader
  /// needs, and it stays stable if the URL is versioned later.
  final String payload;

  /// Human-readable detail, safe to log. Never contains the payload body,
  /// which may hold customer data.
  final String reason;

  const ApiPayloadException(this.payload, this.reason);

  @override
  String toString() => 'ApiPayloadException($payload): $reason';
}
