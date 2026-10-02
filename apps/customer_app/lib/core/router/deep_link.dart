/// Deep linking: the vocabulary of what a link can point at, and how a raw
/// incoming string becomes a typed, well-formed intent.
///
/// WHY THIS IS SEPARATE FROM THE ROUTER
/// -----------------------------------
/// A deep link arrives from outside the app (a notification payload, a shared
/// URL, a cold-start launch argument). It is therefore **untrusted input**:
/// anything can be in it. The router knows how to *render* a screen; it must
/// never decide whether a link is *allowed* to reach one. Keeping parsing and
/// path building here means the dangerous half -- "where does this string want
/// to take the customer" -- is a pure function with no BuildContext, no
/// providers and no I/O, so it can be exhaustively unit-tested.
///
/// The policy half (does this entity exist, is it available, may this customer
/// open it) lives in `deep_link_guard.dart`.
library;

/// The kinds of thing a deep link can point at.
///
/// Every value here must have a real destination registered in `routerProvider`
/// and a case in [deepLinkPathFor]. An entity with no route would turn a
/// well-formed link into a dead end, which is exactly what the guard's
/// fallback exists to prevent.
enum DeepLinkEntity { product, shop, search, offer, notification }

/// Backend ids are UUIDs, EAN-13 barcodes and short slugs. Anything longer, or
/// containing a `/`, `?`, `#` or whitespace, is rejected before it can be
/// interpolated into a route -- a link must never be able to redirect the
/// customer to a *different* route by smuggling path separators into an id.
const int kMaxDeepLinkIdLength = 64;

final RegExp _safeIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

/// Longest search text accepted from a link.
///
/// The search screen enforces its own limits; this only stops a crafted link
/// from pushing a megabyte of text through the router's query parameters.
const int kMaxDeepLinkQueryLength = 120;

/// A parsed deep link, before any policy has been applied.
///
/// An intent can be **unwell-formed** (`/product/` with no id, a 10kb id, a
/// path traversal attempt). That is a normal outcome, not an error: the parser
/// reports it through [isWellFormed] and the guard turns it into a graceful
/// fallback rather than letting it reach the router.
class DeepLinkIntent {
  final DeepLinkEntity entity;

  /// Identifier of the target entity. Empty for [DeepLinkEntity.search] and
  /// [DeepLinkEntity.notification], which are not id-addressed.
  final String id;

  /// Search text; only meaningful for [DeepLinkEntity.search].
  final String query;

  const DeepLinkIntent({required this.entity, this.id = '', this.query = ''});

  /// A search link carrying [query].
  const DeepLinkIntent.search(this.query)
    : entity = DeepLinkEntity.search,
      id = '';

  /// A link to the notification inbox.
  const DeepLinkIntent.notifications()
    : entity = DeepLinkEntity.notification,
      id = '',
      query = '';

  /// Whether this intent carries everything its entity requires.
  ///
  /// Kept separate from the guard's *policy* checks on purpose: this only
  /// answers "is the string well formed", never "does the entity exist".
  bool get isWellFormed {
    switch (entity) {
      case DeepLinkEntity.product:
      case DeepLinkEntity.shop:
      case DeepLinkEntity.offer:
        return _safeIdPattern.hasMatch(id);
      case DeepLinkEntity.search:
        return query.trim().isNotEmpty;
      case DeepLinkEntity.notification:
        return true;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is DeepLinkIntent &&
      other.entity == entity &&
      other.id == id &&
      other.query == query;

  @override
  int get hashCode => Object.hash(entity, id, query);

  @override
  String toString() => 'DeepLinkIntent(${entity.name}, id: $id, q: $query)';
}

/// Percent-encodes [value] for use in a query string.
///
/// Uses `Uri.encodeQueryComponent`, which escapes `&`, `=` and `?`. Building
/// the query by hand with raw interpolation is how a search term containing an
/// ampersand silently truncates the link and sends the customer to the wrong
/// results.
String encodeDeepLinkQuery(String value) => Uri.encodeQueryComponent(value);

/// The app path for [intent], or `null` when it is not well formed.
///
/// Returning null rather than a best-effort path is deliberate: there is no
/// "close enough" destination for a link whose id is empty or unsafe. The
/// caller falls back instead.
String? deepLinkPathFor(DeepLinkIntent intent) {
  if (!intent.isWellFormed) return null;
  switch (intent.entity) {
    case DeepLinkEntity.product:
      return '/product/${intent.id}';
    case DeepLinkEntity.shop:
      return '/shop/${intent.id}';
    case DeepLinkEntity.search:
      return '/search?q=${encodeDeepLinkQuery(intent.query.trim())}';
    case DeepLinkEntity.offer:
      return '/offer/${intent.id}';
    case DeepLinkEntity.notification:
      return '/notifications';
  }
}

/// Safe landing place when a link cannot be opened.
///
/// Home is deliberately the only choice: it is reachable from every auth state
/// and never itself gated, so a fallback can never bounce the customer into
/// another redirect loop.
const String kDeepLinkFallbackPath = '/';

/// Parses [raw] into a [DeepLinkIntent], or `null` when it targets nothing the
/// app recognises.
///
/// Accepts every shape the platform can hand us:
///
///  * an app-relative path — `/product/abc123`
///  * a bare entity path — `product/abc123`
///  * a custom scheme — `passly://product/abc123`
///  * a universal / https link — `https://passly.app/product/abc123`
///  * a query-string search — `/search?q=dove%20shampoo`
///
/// Unrecognised paths return `null` rather than throwing, so a link to a route
/// this build has not shipped yet degrades to the fallback.
DeepLinkIntent? parseDeepLink(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;

  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

  // A custom-scheme link puts the ENTITY IN THE AUTHORITY and the id in the
  // path: `passly://product/abc123` -> authority "product", path "/abc123".
  // An https or relative path puts both in the path:
  // `https://host/product/abc123` and `product/abc123` -> segments
  // ["product", "abc123"].
  //
  // Reading only the path (the obvious first attempt) silently breaks every
  // `passly://` link, because the first path segment there is the *id* and
  // "abc123" is not an entity the switch recognises, so the link parses to
  // null. Splitting the two shapes here is what makes one parser serve
  // notification payloads, shared URLs and app-relative paths alike.
  final isCustomScheme =
      uri.scheme.isNotEmpty && uri.scheme != 'http' && uri.scheme != 'https';

  late final String head;
  late final String idSegment;
  if (isCustomScheme) {
    head = uri.hasAuthority ? uri.authority.toLowerCase() : '';
    idSegment = segments.isNotEmpty ? segments.first : '';
  } else {
    head = segments.isNotEmpty ? segments.first.toLowerCase() : '';
    idSegment = segments.length > 1 ? segments[1] : '';
  }

  if (head == 'search') {
    // Search is addressable as `/search?q=dove`, `/search/dove` or
    // `passly://search/dove`.
    final fromQuery = uri.queryParameters['q'] ?? uri.queryParameters['query'];
    final text = (fromQuery != null && fromQuery.trim().isNotEmpty)
        ? fromQuery.trim()
        : idSegment;
    if (text.isEmpty || text.length > kMaxDeepLinkQueryLength) return null;
    return DeepLinkIntent.search(text);
  }

  if (head == 'notifications' || head == 'notification') {
    return const DeepLinkIntent.notifications();
  }

  if (idSegment.isEmpty || idSegment.length > kMaxDeepLinkIdLength) return null;

  switch (head) {
    case 'product':
    case 'products':
      return DeepLinkIntent(entity: DeepLinkEntity.product, id: idSegment);
    case 'shop':
    case 'shops':
    case 'store':
      return DeepLinkIntent(entity: DeepLinkEntity.shop, id: idSegment);
    case 'offer':
    case 'offers':
    case 'promo':
      return DeepLinkIntent(entity: DeepLinkEntity.offer, id: idSegment);
    default:
      return null;
  }
}
