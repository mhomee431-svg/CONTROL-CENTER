import '../utils/money.dart';
import '../router/deep_link.dart';
import 'share_safety.dart';

/// A share, fully composed and checked, ready to hand to the platform.
///
/// Immutable and platform-free on purpose: composing is pure so every rule
/// about what may be shared is unit-testable without a device, and so a share
/// can be previewed or logged without opening a sheet.
class ShareContent {
  /// Title/subject line (the "Re:"/subject some apps show).
  final String subject;

  /// The human-readable message. **Never contains an id or a credential.**
  final String message;

  /// Deep link back into the app, when one can be built safely. Null is a
  /// legitimate outcome, not a failure: see [buildShareUrl].
  final String? url;

  const ShareContent({required this.subject, required this.message, this.url});

  /// True when this share carries a usable link.
  bool get hasLink => url != null && url!.isNotEmpty;

  /// The exact string the platform receives, link appended on its own line.
  String get fullText => hasLink ? '$message\n$url' : message;
}

/// Public web origin that shared links are built on.
///
/// WHY THIS IS NOT [EnvConfig.apiBaseUrl]
/// ---------------------------------------
/// The API base URL points at infrastructure: `http://10.0.2.2:8000` in the
/// Android emulator, `http://localhost:8000` on a laptop, a staging hostname in
/// preview builds. Building a share link from it would publish the company's
/// internal network topology to every recipient, and the link would not open
/// for anyone who is not on that network anyway.
///
/// So the share origin is a separate, explicit, opt-in `--dart-define`. When it
/// is absent -- which is the default, including in dev and staging -- [buildShareUrl]
/// returns null and the product or shop is shared as text only. A missing link
/// is a small loss of convenience; a leaked internal host is not recoverable.
class ShareLinkConfig {
  /// `flutter run --dart-define=SHARE_BASE_URL=https://passly.app`
  static const String baseUrl = String.fromEnvironment('SHARE_BASE_URL');

  /// Whether a share link can be produced at all in this build.
  static bool get isEnabled => baseUrl.trim().isNotEmpty;

  /// Builds an absolute share link for [intent], or null when it cannot be done
  /// safely.
  ///
  /// Returns null in three distinct cases, all of which mean "share the text,
  /// not a link":
  ///
  ///  * the build has no public origin configured;
  ///  * the intent is not well formed (unsafe or missing id) -- reusing
  ///    [deepLinkPathFor] means the share link is resolved by exactly the same
  ///    code that resolves an incoming link, so a share can never point at a
  ///    route that the app does not serve;
  ///  * the resulting link would carry internal material.
  static String? buildShareUrl(DeepLinkIntent intent) {
    if (!isEnabled) return null;
    final path = deepLinkPathFor(intent);
    if (path == null) return null;
    final origin = baseUrl.trim();
    // Trim a trailing slash so the join cannot produce `https://passly.app//product/1`,
    // which is a valid-looking but wrong link.
    final normalized = origin.endsWith('/')
        ? origin.substring(0, origin.length - 1)
        : origin;
    final url = '$normalized$path';
    if (findShareLeaks(url).isNotEmpty) return null;
    return url;
  }
}

/// Picks the identifier a product should be shared under.
///
/// WHY A BARCODE IS PREFERRED OVER THE INTERNAL ID
/// ----------------------------------------------
/// A product master carries several identifiers (EAN, UPC, SKU, MPN). The
/// barcode is *public by definition* -- it is printed on the box, scanned at
/// the till, and typed into search -- so putting it in a URL reveals nothing
/// that is not already in the customer's hand.
///
/// The internal product id is the fallback. It is still route-safe and still
/// confined to the URL (never the prose), but preferring the barcode means the
/// common case shares a number the recipient can verify rather than a database
/// key.
String? preferredProductShareId({
  required String productId,
  List<({String type, String value})> identifiers = const [],
}) {
  // Normalised before comparison: the backend spells the same standard several
  // ways -- "EAN", "ean_13", "UPC-A", "gtin" -- and a set membership test on
  // the raw string silently treats "UPC-A" as an internal reference, sending
  // the share back to the database key instead of the public barcode.
  const publicBarcodeTypes = {'ean', 'ean13', 'upc', 'upca', 'gtin'};
  for (final identifier in identifiers) {
    final type = identifier.type.trim().toLowerCase().replaceAll(
      RegExp('[^a-z0-9]'),
      '',
    );
    if (!publicBarcodeTypes.contains(type)) continue;
    final value = identifier.value.trim();
    if (value.isEmpty) continue;
    // Reuse the deep link's own id validation so a share id is exactly as
    // safe as a link id -- one rule, not two that can drift.
    final probe = DeepLinkIntent(entity: DeepLinkEntity.product, id: value);
    if (deepLinkPathFor(probe) != null) return value;
  }
  final fallback = productId.trim();
  if (fallback.isEmpty) return null;
  final probe = DeepLinkIntent(entity: DeepLinkEntity.product, id: fallback);
  return deepLinkPathFor(probe) != null ? fallback : null;
}

/// Thrown when a composed share would expose a credential or internal detail.
///
/// A crash is the point. A share that leaks a session token is not something to
/// "mostly avoid" -- the sheet is already open by the time a user notices a
/// mistake, and the string is already in a third-party app. Refusing loudly in
/// debug, where it is caught by a test, is the only point at which anyone can
/// still do something about it.
class UnsafeShareContentException implements Exception {
  final List<ShareLeak> leaks;

  const UnsafeShareContentException(this.leaks);

  @override
  String toString() =>
      'UnsafeShareContentException(${leaks.map((l) => l.kind).join(', ')})';
}

/// Asserts that [content] is safe to hand to a third-party app.
///
/// Checks three things, in the order a leak would actually occur:
///
///  1. the **message** (what a human reads) carries no credential -- this is
///     where a debug string interpolation most often slips one in;
///  2. the **message** contains no entity id, because an id in prose is an
///     internal identifier a customer never needs to see;
///  3. the **url** carries no credential or internal host, which catches a
///     badly configured share origin.
///
/// Throws [UnsafeShareContentException] in debug. In release it returns
/// normally, because crashing a customer's share button is a worse failure
/// than a slightly imperfect string, and the leaks it looks for have already
/// been designed out at the composition site.
void assertShareIsSafe(
  ShareContent content, {
  List<String> internalIds = const [],
}) {
  assert(() {
    // Computed outside the message string on purpose: the assert message is
    // only evaluated when the assertion already failed, but the values have to
    // be in scope for it to name them at all.
    final leaks = <ShareLeak>[
      ...findShareLeaks(content.message),
      ...findShareLeaks(content.url),
    ];
    final idLeaks = internalIds
        .where((id) => id.trim().isNotEmpty && content.message.contains(id))
        .toList();
    if (leaks.isEmpty && idLeaks.isEmpty) return true;
    throw UnsafeShareContentException(leaks);
  }(), 'Share content would expose internal material');
}

/// Composes a share for a product the customer is looking at.
///
/// Every field is optional except the name, because the call sites differ: the
/// search result card knows a price and a shop but no barcode, while the
/// product page knows the barcode and the brand. Missing data is omitted
/// rather than rendered as "null" or "â‚¹0".
ShareContent buildProductShareContent({
  required String productName,
  double? price,
  double? mrp,
  int? discountPercent,
  String? shopName,
  double? distanceInKm,
  String? variant,
  String? brand,
  String? productId,
  List<({String type, String value})> identifiers = const [],
}) {
  final name = productName.trim().isEmpty ? 'this product' : productName.trim();
  final buffer = StringBuffer('Check out $name');

  if (variant != null && variant.trim().isNotEmpty) {
    buffer.write(' (${variant.trim()})');
  }
  if (price != null) {
    buffer.write(' â€” â‚¹${formatInr(price)}');
    if (mrp != null && mrp > price) {
      buffer.write(' (MRP â‚¹${formatInr(mrp)})');
    }
    if (discountPercent != null && discountPercent > 0) {
      buffer.write(' Â· $discountPercent% OFF');
    }
  }
  if (shopName != null && shopName.trim().isNotEmpty) {
    buffer.write(' at ${shopName.trim()}');
    if (distanceInKm != null) {
      buffer.write(' (${distanceInKm.toStringAsFixed(1)} km)');
    }
  }
  if (brand != null && brand.trim().isNotEmpty) {
    buffer.write(' Â· ${brand.trim()}');
  }
  buffer.write(' â€” find it near you on Hyperlocal!');

  final shareId = productId == null
      ? null
      : preferredProductShareId(productId: productId, identifiers: identifiers);

  final content = ShareContent(
    subject: 'Product: $name',
    message: buffer.toString(),
    url: shareId == null
        ? null
        : ShareLinkConfig.buildShareUrl(
            DeepLinkIntent(entity: DeepLinkEntity.product, id: shareId),
          ),
  );
  assertShareIsSafe(content, internalIds: [?productId]);
  return content;
}

/// Composes a share for a shop.
///
/// Deliberately shares the shop's *public* attributes -- name, address, rating,
/// how many offers are live -- and nothing else. In particular it never shares
/// raw coordinates: a latitude/longitude pair in a chat message tells the
/// recipient (and anyone the message is forwarded to) exactly where the shop
/// keeps its stock, and the postal address already conveys what a customer
/// actually needs.
ShareContent buildShopShareContent({
  required String shopName,
  String? address,
  double? rating,
  int? reviewCount,
  int? activeOfferCount,
  String? shopId,
  List<String>? categories,
}) {
  final name = shopName.trim().isEmpty ? 'this shop' : shopName.trim();
  final buffer = StringBuffer('Check out $name on Hyperlocal!');

  if (address != null && address.trim().isNotEmpty) {
    buffer.write('\n${address.trim()}');
  }
  if (rating != null) {
    buffer.write('\nRating: ${rating.toStringAsFixed(1)}');
    if (reviewCount != null && reviewCount > 0) {
      buffer.write(' ($reviewCount reviews)');
    }
  }
  if (activeOfferCount != null && activeOfferCount > 0) {
    buffer.write(
      '\n$activeOfferCount active offer${activeOfferCount == 1 ? '' : 's'}',
    );
  }
  if (categories != null && categories.isNotEmpty) {
    final trimmed = categories
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList();
    if (trimmed.isNotEmpty) buffer.write('\n${trimmed.join(' Â· ')}');
  }

  final trimmedId = shopId?.trim();
  final validId =
      trimmedId != null &&
      trimmedId.isNotEmpty &&
      deepLinkPathFor(
            DeepLinkIntent(entity: DeepLinkEntity.shop, id: trimmedId),
          ) !=
          null;

  final content = ShareContent(
    subject: 'Shop: $name',
    message: buffer.toString(),
    url: validId
        ? ShareLinkConfig.buildShareUrl(
            DeepLinkIntent(entity: DeepLinkEntity.shop, id: trimmedId),
          )
        : null,
  );
  assertShareIsSafe(content, internalIds: [?trimmedId]);
  return content;
}
