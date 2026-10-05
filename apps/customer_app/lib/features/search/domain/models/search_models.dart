import 'package:freezed_annotation/freezed_annotation.dart';

part 'search_models.freezed.dart';
part 'search_models.g.dart';

@freezed
abstract class SearchSuggestion with _$SearchSuggestion {
  const factory SearchSuggestion({
    required String text,
    @Default(false) bool isCategory,
    @Default(false) bool isBrand,
  }) = _SearchSuggestion;

  factory SearchSuggestion.fromJson(Map<String, dynamic> json) =>
      _$SearchSuggestionFromJson(json);
}

/// Availability state of a shop's inventory for a product.
enum InventoryAvailability { inStock, outOfStock, lowStock, unknown }

extension InventoryAvailabilityX on InventoryAvailability {
  String get displayLabel => switch (this) {
    InventoryAvailability.inStock => 'IN STOCK',
    InventoryAvailability.lowStock => 'LOW STOCK',
    InventoryAvailability.outOfStock => 'OUT OF STOCK',
    InventoryAvailability.unknown => 'UNKNOWN',
  };
}

/// How fresh the inventory signal is.
enum FreshnessLevel { fresh, recent, stale, unknown }

/// Canonical, factual rendering of inventory freshness.
///
/// This is the single source of truth for "how old is this stock data?" copy.
/// Every customer-facing surface (search cards, product details, nearby shops,
/// barcode sheet) must render freshness through this file so two screens can
/// never disagree about the same backend reading.
///
/// ## Why this is deliberately conservative
///
/// The freshness signal is a *claim about the past*, and a wrong claim is worse
/// than no claim. Two rules follow from that:
///
/// 1. **Never invent a timestamp.** If the backend did not report one, the
///    answer is [kFreshnessUnknown] — not "just now".
/// 2. **Never round a real reading into a nicer-sounding one.** A listing
///    updated 0 minutes ago is "just now", not "5 min ago"; one updated
///    3 days ago is "Stale", not a reassuring round number.
///
/// Clock skew is the classic trap: a device whose clock runs ahead produces a
/// *negative* age. We treat that as unknown rather than clamping it to zero and
/// displaying a confident "Updated just now" for data we cannot place in time.

/// Shown when the backend supplied no usable freshness signal.
const String kFreshnessUnknown = 'Unknown';

/// Shown when the reading exists but is too old to act on.
const String kFreshnessStale = 'Stale';

/// Shown for a reading from less than a minute ago.
const String kFreshnessJustNow = 'Updated just now';

/// Explains that a stock reading is a snapshot, not a reservation.
///
/// Required by the discovery contract: availability can change, and the app
/// must never imply an item is guaranteed to still be there on arrival.
const String kFreshnessDisclaimer =
    'Stock shown is the shop\'s last update. Availability can change — '
    'please confirm with the shop before you visit.';

/// Treats the epoch sentinel used by the repositories as "not reported".
///
/// The API layer maps a missing `last_inventory_update` to
/// `DateTime.fromMillisecondsSinceEpoch(0)`. That is a real `DateTime`, so it
/// must be recognised explicitly or every un-dated listing would render as
/// "Stale" after ~56 years.
bool isMissingFreshnessTimestamp(DateTime? timestamp) {
  if (timestamp == null) return true;
  if (timestamp.millisecondsSinceEpoch <= 0) return true;
  return false;
}

/// Formats the customer-facing freshness label for a stock reading.
///
/// [lastUpdated] is when the shop last reported this item's stock, and
/// [backendStatus] is the backend's own classification
/// (`RECENTLY_UPDATED` / `STALE`) when it supplied one.
///
/// Produces exactly one of:
/// * `Updated just now`      — under a minute old
/// * `Updated N min ago`     — under an hour old
/// * `Updated today`         — earlier on the same calendar day
/// * `Updated yesterday`     — the calendar day before
/// * `Stale`                 — older, or explicitly flagged stale by the backend
/// * `Unknown`               — no usable reading
///
/// [now] is injectable so the logic is deterministic under test.
String formatFreshnessText(
  DateTime? lastUpdated, {
  String? backendStatus,
  DateTime? now,
}) {
  // A backend "STALE" verdict wins: it knows the per-source threshold
  // (POS sync vs. manual entry), which a generic client-side guess cannot
  // reproduce.
  if ((backendStatus ?? '').trim().toUpperCase() == 'STALE') {
    return kFreshnessStale;
  }

  if (isMissingFreshnessTimestamp(lastUpdated)) {
    return kFreshnessUnknown;
  }

  // Promoted to non-null by the guard above, so the calendar maths below is
  // safe to read .year/.month/.day directly.
  final updated = lastUpdated!;

  final reference = now ?? DateTime.now();
  final age = reference.difference(updated);

  // Future-dated reading (device/server clock skew). We genuinely do not know
  // how old the data is, so we say so instead of guessing.
  if (age.isNegative) {
    return kFreshnessUnknown;
  }

  if (age.inMinutes < 1) {
    return kFreshnessJustNow;
  }
  if (age.inMinutes < 60) {
    return 'Updated ${age.inMinutes} min ago';
  }

  final today = DateTime(reference.year, reference.month, reference.day);
  final updatedDay = DateTime(updated.year, updated.month, updated.day);
  final dayGap = today.difference(updatedDay).inDays;

  if (dayGap == 0) {
    return 'Updated today';
  }
  if (dayGap == 1) {
    return 'Updated yesterday';
  }
  return kFreshnessStale;
}

/// Whether a freshness label should be visually escalated as a warning.
///
/// Only genuinely old or undated data warrants attention; a reading from
/// earlier today is not something the customer needs to act on.
bool isFreshnessWarning(String label) {
  return label == kFreshnessStale || label == kFreshnessUnknown;
}

/// Central default sort option across all discovery and search screens.
/// Defined centrally rather than separately in multiple screens.
const kDefaultSortOption = SortOption.nearest;

/// Sort options for search results.
enum SortOption {
  /// Nearest shops first (default).
  nearest,

  /// Lowest price first.
  lowestPrice,

  /// Highest rated shops first.
  highestRated,

  /// Most recently updated inventory first.
  recentlyUpdated,

  /// Backend relevance ranking.
  relevance,

  /// In-stock / purchasable results first.
  availability,

  /// Items with active offers / discounts first.
  offers,
}

extension SortOptionExtension on SortOption {
  String get displayName => switch (this) {
    SortOption.nearest => 'Distance (Nearest)',
    SortOption.lowestPrice => 'Price (Lowest First)',
    SortOption.highestRated => 'Rating (Highest First)',
    SortOption.relevance => 'Relevance',
    SortOption.availability => 'Availability',
    SortOption.offers => 'Offers & Deals',
    SortOption.recentlyUpdated => 'Freshness',
  };

  String get shortName => switch (this) {
    SortOption.nearest => 'Distance',
    SortOption.lowestPrice => 'Price',
    SortOption.highestRated => 'Rating',
    SortOption.relevance => 'Relevance',
    SortOption.availability => 'Availability',
    SortOption.offers => 'Offers',
    SortOption.recentlyUpdated => 'Freshness',
  };

  String get apiValue => switch (this) {
    SortOption.nearest => 'nearest',
    SortOption.lowestPrice => 'lowest_price',
    SortOption.highestRated => 'highest_rated',
    SortOption.recentlyUpdated => 'recently_updated',
    SortOption.relevance => 'relevance',
    SortOption.availability => 'availability',
    SortOption.offers => 'offers',
  };
}

/// A single shop's offering of a product, returned by the search engine.
///
/// Answers: "Which nearby shop has this product, at what price, and how far?"
@freezed
abstract class ShopProductResult with _$ShopProductResult {
  const factory ShopProductResult({
    required String id,
    required String productId,
    required String productName,
    required String productImageUrl,
    required String shopId,
    required String shopName,
    required double price,
    required bool isAvailable,
    required double distanceInKm,
    required double shopRating,
    required DateTime lastUpdated,
    String? variant,
    double? mrp,
    String? shopImageUrl,
    String? offerText,
    String? shopAddress,
    double? shopLatitude,
    double? shopLongitude,
    String? category,
    String? brand,
    int? reviewCount,

    /// Whether the shop is currently open, per the backend's opening-hours
    /// evaluation. Null means the backend did not report it (unknown), which
    /// must never be rendered as "Open".
    bool? isOpenNow,

    /// Whether the shop currently accepts orders. Null = unknown.
    bool? isAcceptingOrders,

    @Default(InventoryAvailability.unknown) InventoryAvailability availability,
    @Default(FreshnessLevel.unknown) FreshnessLevel freshness,

    /// The backend's own freshness verdict verbatim (`RECENTLY_UPDATED` /
    /// `STALE`), preserved so the UI can defer to the server's per-source
    /// staleness threshold instead of re-guessing it client-side.
    String? freshnessStatusRaw,
  }) = _ShopProductResult;

  const ShopProductResult._();

  factory ShopProductResult.fromJson(Map<String, dynamic> json) =>
      _$ShopProductResultFromJson(json);

  /// Purchasable only when backend explicitly reports in-stock AND fresh.
  bool get isPurchasableNow =>
      isAvailable &&
      availability == InventoryAvailability.inStock &&
      freshness != FreshnessLevel.stale &&
      freshness != FreshnessLevel.unknown;

  bool get isOutOfStock =>
      availability == InventoryAvailability.outOfStock || !isAvailable;

  bool get hasDiscount => mrp != null && mrp! > price;

  int get discountPercent {
    if (!hasDiscount) return 0;
    return ((mrp! - price) / mrp! * 100).round();
  }

  bool get hasCoordinates => shopLatitude != null && shopLongitude != null;

  /// Whether the distance is a real measurement.
  ///
  /// The backend sends `0.0` when the customer's or the shop's coordinates could
  /// not be resolved, so a raw zero means UNKNOWN — not "you are standing in it".
  /// Lives here rather than in each card so the product-result card and the shop
  /// card cannot drift into disagreeing about the same number.
  bool get hasKnownDistance => distanceInKm > 0;

  /// Whether the shop has any ratings at all.
  ///
  /// A `0` is an absent rating, not a rated shop that scored zero — showing a star
  /// beside "0.0" tells a customer the shop is terrible when it has simply never
  /// been reviewed.
  bool get isRated => shopRating > 0;
}
