import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/utils/relative_time.dart';

part 'product_details_models.freezed.dart';
part 'product_details_models.g.dart';

/// A single attribute of a product (e.g. Color: Red, Size: M).
@freezed
abstract class ProductAttribute with _$ProductAttribute {
  const factory ProductAttribute({
    required String name,
    required List<String> values,
  }) = _ProductAttribute;

  factory ProductAttribute.fromJson(Map<String, dynamic> json) =>
      _$ProductAttributeFromJson(json);
}

/// A product identifier (EAN, UPC, SKU, MPN, etc.).
@freezed
abstract class ProductIdentifier with _$ProductIdentifier {
  const factory ProductIdentifier({
    required String type,
    required String value,
    @Default(false) bool isPrimary,
  }) = _ProductIdentifier;

  factory ProductIdentifier.fromJson(Map<String, dynamic> json) =>
      _$ProductIdentifierFromJson(json);
}

/// A product variant (e.g. "128GB Black", "256GB Blue").
@freezed
abstract class ProductVariant with _$ProductVariant {
  const factory ProductVariant({
    required String id,
    required String name,
    String? sku,
    String? description,
    @Default(<String, String>{}) Map<String, String> attributes,
  }) = _ProductVariant;

  factory ProductVariant.fromJson(Map<String, dynamic> json) =>
      _$ProductVariantFromJson(json);
}

/// GLOBAL PRODUCT MASTER — the single source of truth for a product's
/// static information. This is NOT shop-specific.
@freezed
abstract class ProductMasterDetails with _$ProductMasterDetails {
  const factory ProductMasterDetails({
    required String id,
    required String name,
    required String brand,
    required String category,
    String? subcategory,
    String? description,
    String? shortDescription,
    String? baseUnit,
    double? baseQuantity,
    double? mrp,
    String? priceRange,
    @Default(<String>[]) List<String> imageUrls,
    @Default(<ProductVariant>[]) List<ProductVariant> variants,
    @Default(<ProductAttribute>[]) List<ProductAttribute> attributes,
    @Default(<ProductIdentifier>[]) List<ProductIdentifier> identifiers,
    @Default(false) bool isSaved,
  }) = _ProductMasterDetails;

  factory ProductMasterDetails.fromJson(Map<String, dynamic> json) =>
      _$ProductMasterDetailsFromJson(json);
}

/// SHOP-SPECIFIC INVENTORY — dynamic availability of a product at a
/// particular shop. This is NOT part of the global product master.
@freezed
abstract class ShopInventoryOffer with _$ShopInventoryOffer {
  const factory ShopInventoryOffer({
    required String shopId,
    required String shopName,
    required String shopImageUrl,
    required double price,
    double? mrp,
    required double distanceInKm,
    required double rating,
    required bool isAvailable,
    required DateTime lastUpdated,
    String? stockStatus,
    String? freshnessStatus,
    String? offerText,

    /// Whether the shop is open right now, per the backend's opening-hours
    /// evaluation. Null means the backend did not report it (unknown) and must
    /// never be rendered as "Open".
    bool? isOpenNow,

    /// Whether the shop is currently accepting orders. Null = unknown.
    bool? isAcceptingOrders,
  }) = _ShopInventoryOffer;

  /// Required by freezed so the computed getters below can live on the model.
  const ShopInventoryOffer._();

  factory ShopInventoryOffer.fromJson(Map<String, dynamic> json) =>
      _$ShopInventoryOfferFromJson(json);

  /// True only when the backend explicitly reported the shop as open.
  bool get isConfirmedOpen => isOpenNow == true;

  /// True only when the backend explicitly reported the shop as closed.
  bool get isConfirmedClosed => isOpenNow == false;

  /// Out of stock when the backend says unavailable, or reports an explicit
  /// out-of-stock status. An unknown status alone is not treated as out of
  /// stock — absence of a status is not evidence of absence of stock.
  bool get isOutOfStock {
    if (!isAvailable) return true;
    final status = (stockStatus ?? '').toUpperCase();
    return status.contains('OUT_OF_STOCK') || status.contains('OUT-OF-STOCK');
  }

  /// Whether this offer carries a genuine discount off MRP.
  bool get hasDiscount => mrp != null && mrp! > price;

  int get discountPercent {
    if (!hasDiscount) return 0;
    return ((mrp! - price) / mrp! * 100).round();
  }
}

/// Combined view for the Product Details screen.
/// Keeps [product] (global master) and [shopOffers] (shop inventory)
/// as separate, clearly-distinguished fields.
@freezed
abstract class ProductDetails with _$ProductDetails {
  const factory ProductDetails({
    required ProductMasterDetails product,
    @Default(<ShopInventoryOffer>[]) List<ShopInventoryOffer> shopOffers,

    /// Whether this payload came from the local cache rather than the network.
    ///
    /// This is the field that stops the app from presenting old data as live.
    /// Product master data (name, brand, images, description) is stable enough
    /// to cache, so serving it offline is good behaviour — but only if the UI
    /// says so. Without this flag a cached page is indistinguishable from a
    /// fresh one, and the customer has no way to know the prices they are
    /// looking at may be out of date.
    @Default(false) bool servedFromCache,

    /// When this payload was cached. Null for live data.
    ///
    /// Drives the "Last updated …" line. Null whenever [servedFromCache] is
    /// false, because a live response is current by definition and dating it
    /// would be noise.
    DateTime? cachedAt,
  }) = _ProductDetails;

  /// Required by freezed so the computed getters below can live on the model.
  const ProductDetails._();

  factory ProductDetails.fromJson(Map<String, dynamic> json) =>
      _$ProductDetailsFromJson(json);

  /// True when the customer is looking at cached data and the screen must say
  /// so rather than implying the content is current.
  bool get isStale => servedFromCache;

  /// Whether the SHOP-side data on this payload is verified-current.
  ///
  /// The product master (name, brand, images, description) is stable enough to
  /// cache, so serving it offline is genuinely useful. The shop-side data is
  /// not: stock, price, offers and opening hours all change without notice, and
  /// a cached "In stock at 3 nearby shops" is a claim about the world that may
  /// no longer be true.
  ///
  /// This single flag gates every dynamic claim on the screen. It exists in the
  /// model rather than being checked ad hoc in each widget because a widget that
  /// forgets the check is a widget that lies, and there were already several
  /// places rendering `isAvailable`/`hasDiscount` without consulting provenance.
  bool get hasLiveShopData => !servedFromCache;

  /// Shop offers that may be presented as CURRENT.
  ///
  /// Empty when the payload came from cache. Returning an empty list (rather
  /// than the cached offers) is the deliberate choice: showing the old rows with
  /// a warning above them still lets a customer read "In Stock" off a tile, and
  /// a stale tile is worse than no tile because it invites a wasted trip to the
  /// shop. The customer can always retry to get the real list.
  List<ShopInventoryOffer> get liveOffers =>
      servedFromCache ? const <ShopInventoryOffer>[] : shopOffers;

  /// "Last updated …" label, or null when the data is live.
  ///
  /// Null (not "just now") for live data: there is nothing to disclose about
  /// data the server just sent, and a timestamp there would suggest the
  /// numbers age on their own.
  String? get lastUpdatedLabel {
    if (!servedFromCache) return null;
    return formatLastUpdated(cachedAt);
  }

  /// Offers that are actually purchasable now, cheapest first.
  ///
  /// A price comparison built on out-of-stock listings would be misleading, so
  /// this excludes them; [comparableOffers] keeps them for the full list.
  ///
  /// Empty for cached data — see [liveOffers].
  List<ShopInventoryOffer> get comparableOffers {
    final live = liveOffers.where((o) => !o.isOutOfStock).toList();
    live.sort((a, b) => a.price.compareTo(b.price));
    return live;
  }

  /// Every offer, cheapest first — including out-of-stock shops, so the
  /// customer can still see who normally stocks the item.
  List<ShopInventoryOffer> get allOffersSorted {
    final all = [...liveOffers];
    all.sort((a, b) => a.price.compareTo(b.price));
    return all;
  }

  /// The lowest price among in-stock offers, or null when none exist.
  ///
  /// Null rather than a fabricated number: with no live offer there is no
  /// current price to show. Cached data yields null for the same reason — a
  /// remembered price is not a current one.
  double? get lowestPrice {
    final live = comparableOffers;
    if (live.isEmpty) return null;
    return live.first.price;
  }

  /// The highest price among in-stock offers, for the comparison range.
  double? get highestPrice {
    final live = comparableOffers;
    if (live.isEmpty) return null;
    return live.last.price;
  }

  /// How much the cheapest and dearest in-stock shops differ by.
  /// Null when there is nothing to compare (fewer than two live offers).
  double? get priceSpread {
    final low = lowestPrice;
    final high = highestPrice;
    if (low == null || high == null || high <= low) return null;
    return high - low;
  }

  /// Offers carrying a genuine discount or an active offer label.
  ///
  /// Empty for cached data. A promotion that expired an hour ago must not be
  /// shown as a live deal, and an offer's end time is not in the cached payload
  /// — so the only safe reading of a cached offer is "unknown", not "current".
  List<ShopInventoryOffer> get offersWithDeals {
    final deals = liveOffers
        .where((o) => o.hasDiscount || (o.offerText?.isNotEmpty ?? false))
        .toList();
    // Biggest saving first so the most useful deal leads.
    deals.sort((a, b) => b.discountPercent.compareTo(a.discountPercent));
    return deals;
  }

  /// Cheapest in-stock shop, or null. Used for the "lowest price" fact line —
  /// never rendered as a subjective "best" claim.
  ShopInventoryOffer? get cheapestOffer =>
      comparableOffers.isEmpty ? null : comparableOffers.first;

  /// Nearest shop that is in stock, or null.
  ShopInventoryOffer? get nearestInStockOffer {
    final live = comparableOffers;
    if (live.isEmpty) return null;
    return live.reduce(
      (a, b) => a.distanceInKm <= b.distanceInKm ? a : b,
    );
  }
}
