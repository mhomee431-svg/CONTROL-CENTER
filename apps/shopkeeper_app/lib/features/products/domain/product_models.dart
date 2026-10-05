/// Distinct, case-insensitely sorted non-blank values of [pick] across
/// [items] — the option list behind a filter sheet's Category / Brand
/// pickers. Sourced from real rows so a filter can never be offered that
/// matches nothing; an empty result tells the sheet to hide that picker.
List<String> distinctFilterValues(
  Iterable<ShopProductItem> items,
  String? Function(ShopProductItem) pick,
) {
  final values = <String>{};
  for (final item in items) {
    final value = pick(item)?.trim();
    if (value != null && value.isNotEmpty) values.add(value);
  }
  return values.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
}

/// A product listed under the shopkeeper's own shop
/// (shop_products + inventory projection).
///
/// Maps the PRODUCT MASTER + PRODUCT VARIANT + SHOP PRODUCT architecture:
/// master metadata (brand/category/image) is a read-only reference; the
/// shopkeeper manages the shop-specific association (price/stock/availability).
class ShopProductItem {
  const ShopProductItem({
    required this.id,
    required this.name,
    required this.status,
    required this.price,
    this.mrp,
    this.sku,
    this.variant,
    this.brand,
    this.category,
    this.imageUrl,
    required this.isActive,
    required this.isAvailable,
    required this.quantity,
    required this.stockStatus,
    this.freshnessStatus,
    this.lastUpdated,
    this.source,
    this.updatedBy,
    this.lowStockThreshold,
  });

  final int id;
  final String name;
  final String? sku;

  /// Product variant label (e.g. "500ml", "Red / M"); falls back to SKU.
  final String? variant;

  /// Brand name from the Product Master (read-only reference).
  final String? brand;

  /// Category name from the Product Master (read-only reference).
  final String? category;

  /// Primary product image URL (read-only reference from the master).
  final String? imageUrl;

  final String status;
  final double price;
  final double? mrp;
  final bool isActive;
  final bool isAvailable;
  final int quantity;
  final String stockStatus;

  /// Inventory freshness tier from the backend
  /// (RECENTLY_UPDATED / FRESH / STALE / null when unknown).
  final String? freshnessStatus;

  /// Last inventory/price update timestamp (ISO-8601, nullable).
  final DateTime? lastUpdated;

  /// Inventory source reported by the server (MANUAL / BARCODE_SCAN /
  /// POS_INTEGRATION / EXCEL_UPLOAD / SYSTEM). Rendered verbatim-derived —
  /// the server owns the vocabulary, the client only maps display labels.
  final String? source;

  /// Display name of whoever last updated the inventory (server-resolved).
  final String? updatedBy;

  /// Per-listing low-stock threshold the server reported (`null` when the
  /// backend did not send one; callers fall back to the platform default of 5
  /// — the same default the backend applies on create).
  final int? lowStockThreshold;

  bool get isOutOfStock => stockStatus == 'OUT_OF_STOCK';
  bool get isLowStock => stockStatus == 'LOW_STOCK';

  /// True when the shopkeeper (or the platform) discontinued this listing.
  ///
  /// `DISCONTINUED` is a `ShopProduct.status`, NOT a `stock_status` — the
  /// backend's stock enum has no such member, so reading only [stockStatus]
  /// would render a discontinued listing as "In stock".
  bool get isDiscontinued => status == 'DISCONTINUED';

  /// True when the listing is out of play: either explicitly discontinued or
  /// switched off via the `is_active` flag.
  ///
  /// This is the guard for every destructive write — a withdrawn listing must
  /// not offer "Reactivate" twice, and must not be counted as sellable.
  bool get isWithdrawn => isDiscontinued || !isActive;

  /// The ONE listing-lifecycle state every screen renders (spec §74/§75).
  ///
  /// A discontinued status outranks the `is_active` boolean, because that is
  /// exactly the combination the server produces after a deactivate PATCH —
  /// see [ListingStateView] for why the two fields must be reconciled together.
  ListingStateView get listingState => isDiscontinued
      ? ListingStateView.discontinued
      : (isActive ? ListingStateView.active : ListingStateView.inactive);

  /// The ONE stock state every screen renders.
  ///
  /// A discontinued listing deliberately outranks its remaining stock count:
  /// the shopkeeper needs to see "Discontinued", not a stale "In stock" chip.
  StockStateView get stockState => isDiscontinued
      ? StockStateView.discontinued
      : StockStateView.of(stockStatus);

  bool get isStale => freshnessStatus == 'STALE';
  bool get isFresh => freshnessStatus == 'RECENTLY_UPDATED';

  /// True when the backend reported a freshness tier we can render.
  bool get hasFreshness => freshnessStatus != null;

  /// Accepts BOTH backend key shapes:
  ///   - inventory overview:  `shop_product_id`
  ///   - product endpoints:   `id` (serialize_product / create / patch)
  /// Parsing `id ?? shop_product_id` keeps PATCH/update calls correct for
  /// every screen — a zero id would break every inventory write.
  static int _parseId(Map<String, dynamic> json) =>
      (json['id'] as num?)?.toInt() ??
      (json['shop_product_id'] as num?)?.toInt() ??
      0;

  static DateTime? _parseDate(Object? raw) {
    if (raw is DateTime) return raw;
    if (raw is String && raw.isNotEmpty) {
      return DateTime.tryParse(raw);
    }
    return null;
  }

  factory ShopProductItem.fromJson(Map<String, dynamic> json) =>
      ShopProductItem(
        id: _parseId(json),
        name: json['name'] as String? ?? 'Unnamed',
        sku: json['sku'] as String?,
        variant: json['variant'] as String?,
        brand: json['brand'] as String?,
        category: json['category'] as String?,
        imageUrl: json['image_url'] as String?,
        status: json['status'] as String? ?? 'ACTIVE',
        price: (json['price'] as num?)?.toDouble() ?? 0,
        mrp: (json['mrp'] as num?)?.toDouble(),
        isActive: json['is_active'] as bool? ?? false,
        isAvailable: json['is_available'] as bool? ?? false,
        quantity: (json['quantity'] as num?)?.toInt() ?? 0,
        stockStatus: json['stock_status'] as String? ?? 'UNKNOWN',
        freshnessStatus: json['freshness_status'] as String?,
        lastUpdated:
            _parseDate(json['last_updated'] ?? json['last_inventory_update']),
        source: json['source'] as String?,
        updatedBy: json['updated_by'] as String?,
        lowStockThreshold: (json['low_stock_threshold'] as num?)?.toInt(),
      );

  ShopProductItem copyWith({
    bool? isActive,
    bool? isAvailable,
    int? quantity,
    String? stockStatus,
    String? status,
    double? price,
    double? mrp,
    String? freshnessStatus,
    DateTime? lastUpdated,
    String? source,
    String? updatedBy,
  }) =>
      ShopProductItem(
        id: id,
        name: name,
        sku: sku,
        variant: variant,
        brand: brand,
        category: category,
        imageUrl: imageUrl,
        // Listing lifecycle is a WRITABLE facet: deactivating a listing changes
        // `status`, and `is_active` moves with it. Before this both fields were
        // hard-copied, so a copyWith could silently resurrect a discontinued
        // listing as an active one.
        status: status ?? this.status,
        price: price ?? this.price,
        mrp: mrp ?? this.mrp,
        isActive: isActive ?? this.isActive,
        isAvailable: isAvailable ?? this.isAvailable,
        quantity: quantity ?? this.quantity,
        stockStatus: stockStatus ?? this.stockStatus,
        freshnessStatus: freshnessStatus ?? this.freshnessStatus,
        lastUpdated: lastUpdated ?? this.lastUpdated,
        source: source ?? this.source,
        updatedBy: updatedBy ?? this.updatedBy,
      );
}

/// Inventory overview summary (same shape as dashboard product stats).
typedef InventorySummary = ({
  int total,
  int active,
  int inStock,
  int lowStock,
  int outOfStock,
  int totalUnits,
  /// Listings whose backend freshness tier is `STALE`.
  ///
  /// Served by the backend in the summary counts, so a home-screen badge can
  /// read it without downloading every listing to count them. A backend that
  /// predates the field reports 0 rather than failing the whole read.
  int stale,
});

InventorySummary inventorySummaryFromJson(Map<String, dynamic> json) => (
      total: (json['total'] as num?)?.toInt() ?? 0,
      active: (json['active'] as num?)?.toInt() ?? 0,
      inStock: (json['in_stock'] as num?)?.toInt() ?? 0,
      lowStock: (json['low_stock'] as num?)?.toInt() ?? 0,
      outOfStock: (json['out_of_stock'] as num?)?.toInt() ?? 0,
      totalUnits: (json['total_units'] as num?)?.toInt() ?? 0,
      stale: (json['stale'] as num?)?.toInt() ?? 0,
    );

class InventoryOverview {
  const InventoryOverview({
    required this.items,
    required this.summary,
    this.fromCache = false,
  });

  final List<ShopProductItem> items;
  final InventorySummary summary;

  /// True when this overview was rebuilt from the device's offline snapshot
  /// instead of a live response. The backend NEVER sends this key; it exists
  /// purely so the UI and tests can distinguish "fresh" from "last synced".
  final bool fromCache;

  factory InventoryOverview.fromJson(Map<String, dynamic> json) {
    // Summary carries extra keys beyond the record fields.
    final raw = Map<String, dynamic>.from(json['summary'] as Map? ?? const {});
    raw.putIfAbsent('inactive', () => 0);
    return InventoryOverview(
      items: ((json['items'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ShopProductItem.fromJson)
          .toList(growable: false),
      summary: inventorySummaryFromJson(raw),
    );
  }

  /// Rebuilds an overview from the offline snapshot — always [fromCache].
  factory InventoryOverview.fromSnapshot(Map<String, dynamic> json) {
    final live = InventoryOverview.fromJson(json);
    return InventoryOverview(
      items: live.items,
      summary: live.summary,
      fromCache: true,
    );
  }
}
/// Server-authoritative inventory stock state (req 21/25).
///
/// The backend owns the vocabulary and sends it verbatim. Two server enums
/// feed this one view, because a listing can be discontinued independently of
/// how much stock is left on the shelf:
///
///   - `Inventory.stock_status` → IN_STOCK / LOW_STOCK / LIMITED_STOCK /
///     OUT_OF_STOCK / UNKNOWN / PRE_ORDER / BACK_ORDER
///   - `ShopProduct.status`     → ACTIVE / INACTIVE / DISCONTINUED / …
///
/// [ShopProductItem.stockState] is the single place that decides how the two
/// combine, so a discontinued listing can never render as "In stock".
///
/// The client NEVER re-declares its own enum duplicate — it only maps the
/// received value to one shared display label, so a brand new server state
/// still renders (humanised) instead of throwing on an unknown enum constant.
/// Every screen reads stock state through this one helper, so the mapping can
/// never drift between features.
class StockStateView {
  const StockStateView._(this.value, this.label);

  /// Canonical server value this view maps onto.
  ///
  /// Aliases collapse onto one canonical state so counts and filters stay
  /// consistent (e.g. `LIMITED_STOCK` and `BACK_ORDER` both report
  /// `LOW_STOCK`), which means this is NOT always the raw value received.
  final String value;

  /// Shopkeeper-facing label.
  final String label;

  static const inStock = StockStateView._('IN_STOCK', 'In stock');
  static const lowStock = StockStateView._('LOW_STOCK', 'Low stock');
  static const outOfStock = StockStateView._('OUT_OF_STOCK', 'Out of stock');
  static const unknown = StockStateView._('UNKNOWN', 'Unknown');
  static const discontinued =
      StockStateView._('DISCONTINUED', 'Discontinued');

  /// Values the server is known to emit → canonical view. Aliases resolve to
  /// the same canonical state so counts and filters stay consistent.
  static const _known = <String, StockStateView>{
    'IN_STOCK': inStock,
    'PRE_ORDER': inStock,
    'LOW_STOCK': lowStock,
    'LIMITED_STOCK': lowStock,
    'BACK_ORDER': lowStock,
    'OUT_OF_STOCK': outOfStock,
    'UNKNOWN': unknown,
    'DISCONTINUED': discontinued,
    // Legacy misspelling kept as an alias so an older payload still renders.
    'DISCONTINUOUS': discontinued,
  };

  /// Resolves any server value (never throws).
  factory StockStateView.of(String? serverValue) {
    final key = (serverValue ?? '').trim().toUpperCase();
    if (key.isEmpty) return unknown;
    return _known[key] ?? StockStateView._(key, _humanize(key));
  }

  static String _humanize(String raw) {
    final words = raw
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0] + part.substring(1).toLowerCase());
    final joined = words.join(' ').trim();
    return joined.isEmpty ? 'Unknown' : joined;
  }

  bool get isOutOfStock => value == 'OUT_OF_STOCK';
  bool get isLowStock => value == 'LOW_STOCK';
  bool get isInStock => value == 'IN_STOCK';
  bool get isDiscontinued => value == 'DISCONTINUED';
  bool get isUnknown => value == 'UNKNOWN';
}

/// The ONE listing-lifecycle state every screen renders (spec §74 / §75).
///
/// `ShopProduct.status` (ACTIVE / INACTIVE / DISCONTINUED / …) and the
/// `is_active` boolean are **two server fields describing one thing**, and a
/// deactivated listing can leave them disagreeing: the approved write is
/// `PATCH /shops/{id}/products/{pid}` with `{"status": "DISCONTINUED"}`, and
/// the backend sets the status while `is_active` keeps its previous value.
/// Reading either field on its own therefore lets a withdrawn listing still
/// render as "Active".
///
/// [ShopProductItem.listingState] is the single place that reconciles them —
/// the same shape as [ShopProductItem.stockState], which already merges
/// `stock_status` and `status` — so the details sheet, the list row and the
/// Discontinued slice can never contradict each other.
///
/// A future server status degrades to a humanised label instead of throwing
/// (§126), and the client never re-declares its own enum duplicate (§126).
class ListingStateView {
  const ListingStateView._(this.value, this.label);

  /// Canonical server `ShopProduct.status` this view maps onto.
  final String value;

  /// Shopkeeper-facing label.
  final String label;

  static const active = ListingStateView._('ACTIVE', 'Active');
  static const inactive = ListingStateView._('INACTIVE', 'Inactive');
  static const discontinued =
      ListingStateView._('DISCONTINUED', 'Discontinued');

  /// Values the server is known to emit → canonical view.
  static const _known = <String, ListingStateView>{
    'ACTIVE': active,
    'APPROVED': active,
    'INACTIVE': inactive,
    'REJECTED': inactive,
    'PENDING_REVIEW': inactive,
    'DRAFT': inactive,
    'DISCONTINUED': discontinued,
    // Legacy misspelling kept as an alias so an older payload still renders.
    'DISCONTINUOUS': discontinued,
  };

  /// Resolves any server status (never throws).
  factory ListingStateView.of(String? serverStatus) {
    final key = (serverStatus ?? '').trim().toUpperCase();
    if (key.isEmpty) return inactive;
    return _known[key] ?? ListingStateView._(key, _humanize(key));
  }

  static String _humanize(String raw) {
    final words = raw
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0] + part.substring(1).toLowerCase());
    final joined = words.join(' ').trim();
    return joined.isEmpty ? 'Unknown' : joined;
  }

  bool get isActive => value == 'ACTIVE';
  bool get isInactive => value == 'INACTIVE';
  bool get isDiscontinued => value == 'DISCONTINUED';
}

/// Result of `POST …/products/{id}/stock-adjustments` — the server-computed
/// truth after a delta update (never a client-side guess).
class StockAdjustmentResult {
  const StockAdjustmentResult({
    required this.shopProductId,
    required this.previousQuantity,
    required this.quantityAdjustment,
    required this.newQuantity,
    required this.stockStatus,
    this.adjustmentType,
    this.lastInventoryUpdate,
    this.source,
    this.freshnessStatus,
  });

  final int shopProductId;
  final int previousQuantity;
  final int quantityAdjustment;
  final int newQuantity;

  /// Server stock state string after the update.
  final String stockStatus;
  final String? adjustmentType;
  final DateTime? lastInventoryUpdate;

  /// Who last moved this stock (`EXCEL_UPLOAD`, `POS_SYNC`, `MANUAL`, ...).
  final String? source;

  /// How current that write is (`RECENTLY_UPDATED`, `STALE`, ...).
  ///
  /// Null from an older server rather than a guess: the confirmation panel
  /// renders nothing at all when all three facts are missing, and an invented
  /// "Unknown" freshness would read as a real measurement.
  final String? freshnessStatus;

  StockStateView get stockState => StockStateView.of(stockStatus);

  factory StockAdjustmentResult.fromJson(Map<String, dynamic> json) =>
      StockAdjustmentResult(
        shopProductId: (json['shop_product_id'] as num?)?.toInt() ?? 0,
        previousQuantity: (json['previous_quantity'] as num?)?.toInt() ?? 0,
        quantityAdjustment: (json['quantity_adjustment'] as num?)?.toInt() ?? 0,
        newQuantity: (json['new_quantity'] as num?)?.toInt() ?? 0,
        stockStatus: json['stock_status'] as String? ?? 'UNKNOWN',
        adjustmentType: json['adjustment_type'] as String?,
        lastInventoryUpdate:
            ShopProductItem._parseDate(json['last_inventory_update']),
        source: json['source'] as String?,
        freshnessStatus: json['freshness_status'] as String?,
      );
}

/// One row of a product's inventory audit trail.
///
/// The backend returns three entry shapes discriminated by `type`:
///   `movement`     — quantity_change / quantity_before / quantity_after /
///                    movement_type / source / notes
///   `adjustment`   — adjustment_type / quantity_adjustment / reason
///   `price_change` — old_price / new_price / old_mrp / new_mrp /
///                    change_source
/// Every field is optional so an unknown future shape still renders instead
/// of crashing the history view.
class ProductHistoryEntry {
  const ProductHistoryEntry({
    required this.type,
    this.occurredAt,
    this.quantityChange,
    this.quantityBefore,
    this.quantityAfter,
    this.movementType,
    this.source,
    this.notes,
    this.adjustmentType,
    this.quantityAdjustment,
    this.reason,
    this.oldPrice,
    this.newPrice,
    this.oldMrp,
    this.newMrp,
    this.changeSource,
    this.actor,
    this.actorId,
  });

  /// `movement` | `adjustment` | `price_change`.
  final String type;
  final DateTime? occurredAt;

  // movement
  final int? quantityChange;
  final int? quantityBefore;
  final int? quantityAfter;
  final String? movementType;
  final String? source;
  final String? notes;

  // adjustment
  final String? adjustmentType;
  final int? quantityAdjustment;
  final String? reason;

  // price_change
  final double? oldPrice;
  final double? newPrice;
  final double? oldMrp;
  final double? newMrp;
  final String? changeSource;

  /// Who performed the change, as reported by the backend
  /// (`movement.created_by` / `adjustment.approved_by` /
  /// `price_history.changed_by`, resolved to the user's name).
  ///
  /// Null means the change was automated — an import, a POS sync or a
  /// scheduled job. It is NEVER back-filled with the current user, because
  /// that would misattribute an automated change to whoever is reading it.
  final String? actor;

  /// Raw user id behind [actor]; null for automated changes.
  final int? actorId;

  /// `By <name>` when a user is known, `Automated` when the server reported
  /// no actor — never a guessed name.
  String get actorLabel =>
      (actor != null && actor!.trim().isNotEmpty) ? 'By ${actor!.trim()}' : 'Automated';

  /// Value signature used to de-duplicate a row across PAGES.
  ///
  /// Audit entries carry no id, so two pages are stitched by their content: the
  /// type, the timestamp and the numbers/actor of a change describe it uniquely.
  /// An identical pair of rows would be a genuine duplicate.
  String get signature => [
        type,
        occurredAt?.toUtc().toIso8601String() ?? '',
        quantityChange ?? '',
        quantityAdjustment ?? '',
        quantityBefore ?? '',
        quantityAfter ?? '',
        oldPrice ?? '',
        newPrice ?? '',
        actor ?? '',
      ].join('|');

  /// Signed delta this entry applied to stock (null for price changes).
  int? get stockDelta => quantityChange ??
      quantityAdjustment ??
      (type == 'price_change' ? null : 0);

  factory ProductHistoryEntry.fromJson(Map<String, dynamic> json) =>
      ProductHistoryEntry(
        type: json['type'] as String? ?? 'movement',
        occurredAt: ShopProductItem._parseDate(json['occurred_at']),
        quantityChange: (json['quantity_change'] as num?)?.toInt(),
        quantityBefore: (json['quantity_before'] as num?)?.toInt(),
        quantityAfter: (json['quantity_after'] as num?)?.toInt(),
        movementType: json['movement_type'] as String?,
        source: json['source'] as String?,
        notes: json['notes'] as String?,
        adjustmentType: json['adjustment_type'] as String?,
        quantityAdjustment: (json['quantity_adjustment'] as num?)?.toInt(),
        reason: json['reason'] as String?,
        oldPrice: (json['old_price'] as num?)?.toDouble(),
        newPrice: (json['new_price'] as num?)?.toDouble(),
        oldMrp: (json['old_mrp'] as num?)?.toDouble(),
        newMrp: (json['new_mrp'] as num?)?.toDouble(),
        changeSource: json['change_source'] as String?,
        actor: json['actor'] as String?,
        actorId: (json['actor_id'] as num?)?.toInt(),
      );
}

/// One stock adjustment in a product's adjustment-only audit trail.
///
/// Adjustments are the operator corrections (RESTOCK / DAMAGE / EXPIRY /
/// STOCK_COUNT / CORRECTION …) that move stock by a delta. The server owns the
/// `adjustment_type` vocabulary — this class never enumerates it, so a new
/// server-side type still renders (humanised by the presentation layer).
class StockAdjustmentEntry {
  const StockAdjustmentEntry({
    required this.id,
    required this.quantityAdjustment,
    this.adjustmentType,
    this.reason,
    this.approvedBy,
    this.approvedAt,
    this.createdAt,
  });

  final int id;

  /// Signed delta applied to stock (negative for damage/expiry write-offs).
  final int quantityAdjustment;

  /// Server adjustment type string (RESTOCK, DAMAGE, …).
  final String? adjustmentType;
  final String? reason;
  final int? approvedBy;
  final DateTime? approvedAt;
  final DateTime? createdAt;

  /// When the adjustment was recorded (approval time, else creation time).
  DateTime? get occurredAt => approvedAt ?? createdAt;

  factory StockAdjustmentEntry.fromJson(Map<String, dynamic> json) =>
      StockAdjustmentEntry(
        id: (json['id'] as num?)?.toInt() ?? 0,
        quantityAdjustment:
            (json['quantity_adjustment'] as num?)?.toInt() ?? 0,
        adjustmentType: json['adjustment_type'] as String?,
        reason: json['reason'] as String?,
        approvedBy: (json['approved_by'] as num?)?.toInt(),
        approvedAt: ShopProductItem._parseDate(json['approved_at']),
        createdAt: ShopProductItem._parseDate(json['created_at']),
      );
}

/// Adjustment-only audit trail for one shop product (newest first).
class StockAdjustmentHistory {
  const StockAdjustmentHistory({
    required this.shopProductId,
    required this.adjustments,
  });

  final int shopProductId;
  final List<StockAdjustmentEntry> adjustments;

  bool get isEmpty => adjustments.isEmpty;

  factory StockAdjustmentHistory.fromJson(Map<String, dynamic> json) =>
      StockAdjustmentHistory(
        shopProductId: (json['shop_product_id'] as num?)?.toInt() ?? 0,
        adjustments: ((json['adjustments'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(StockAdjustmentEntry.fromJson)
            .toList(growable: false),
      );
}

/// Result of changing a listing's low-stock threshold.
///
/// The threshold is what converts a quantity into LOW_STOCK, so the server
/// re-derives and returns the new stock state — the client must never compute
/// it locally (that is how a client enum duplicate starts).
class LowStockThresholdResult {
  const LowStockThresholdResult({
    required this.shopProductId,
    required this.previousLowStockThreshold,
    required this.lowStockThreshold,
    required this.quantity,
    required this.stockStatus,
    this.lastInventoryUpdate,
  });

  final int shopProductId;
  final int previousLowStockThreshold;
  final int lowStockThreshold;
  final int quantity;

  /// Server stock state string after the change.
  final String stockStatus;
  final DateTime? lastInventoryUpdate;

  StockStateView get stockState => StockStateView.of(stockStatus);

  factory LowStockThresholdResult.fromJson(Map<String, dynamic> json) =>
      LowStockThresholdResult(
        shopProductId: (json['shop_product_id'] as num?)?.toInt() ?? 0,
        previousLowStockThreshold:
            (json['previous_low_stock_threshold'] as num?)?.toInt() ?? 0,
        lowStockThreshold:
            (json['low_stock_threshold'] as num?)?.toInt() ?? 0,
        quantity: (json['quantity'] as num?)?.toInt() ?? 0,
        stockStatus: json['stock_status'] as String? ?? 'UNKNOWN',
        lastInventoryUpdate:
            ShopProductItem._parseDate(json['last_inventory_update']),
      );
}
/// How many audit entries one history request asks for.
///
/// The history endpoint accepts `limit` 1…200; 50 matches the server's own
/// default, so the first page is exactly what the backend already served and
/// each further page is one bounded request.
const int productHistoryPageSize = 50;

/// Combined audit trail for one shop product (newest first, server-sorted).
class ProductHistoryResult {
  const ProductHistoryResult({
    required this.shopProductId,
    required this.entries,
    this.total,
    this.offset = 0,
    this.limit = 0,
    this.hasMore = false,
    this.currentQuantity,
    this.stockStatus,
    this.received,
  });

  final int shopProductId;
  final List<ProductHistoryEntry> entries;

  /// Total entries the server holds for this product (across all pages).
  final int? total;

  /// Index of the first entry in this page.
  final int offset;

  /// Page size requested for this fetch.
  final int limit;

  /// True when the server holds further entries beyond this page.
  final bool hasMore;

  /// Net stock the server reports for this product right now — the number the
  /// history summary tile shows. Null when the server did not send it (older
  /// backend), in which case the tile is hidden rather than guessed.
  final int? currentQuantity;

  /// Server stock state string for the summary tile (never a client enum).
  final String? stockStatus;

  /// How many rows the SERVER has served for this product across every page
  /// merged into [entries].
  ///
  /// Deliberately separate from `entries.length`: de-duplication across pages
  /// can drop a row, and client-side filtering (the price history hides every
  /// non-price entry) shrinks the visible list — neither may move the server's
  /// window, or a follow-up request would re-fetch or skip a page.
  final int? received;

  /// Rows the server has served so far (falls back to the rows in hand).
  int get servedCount => received ?? entries.length;

  /// The offset a FOLLOW-UP page request must start at.
  int get nextOffset => offset + servedCount;

  /// Parsed entry count.
  int get count => entries.length;

  /// Entries the server still holds beyond the rows in hand — the count
  /// "Load more" offers. Null when the server never reported a total, so the
  /// control asks to load more without claiming a number it cannot know.
  int? get hidden {
    final known = total;
    if (known == null) return null;
    final left = known - entries.length;
    return left > 0 ? left : 0;
  }

  /// This result with [next]'s rows appended — the ONE way two pages of an
  /// audit trail are stitched, so the stock history and the price history page
  /// identically.
  ///
  /// [total]/[hasMore] come from [next]: the last page the server returned is
  /// the one that knows where its window now ends.
  ProductHistoryResult append(ProductHistoryResult next) {
    final seen = entries.map((e) => e.signature).toSet();
    return ProductHistoryResult(
      shopProductId: next.shopProductId == 0 ? shopProductId : next.shopProductId,
      entries: [
        ...entries,
        ...next.entries.where((e) => !seen.contains(e.signature)),
      ],
      total: next.total ?? total,
      // The window still starts where the FIRST page started.
      offset: offset,
      limit: next.limit,
      hasMore: next.hasMore,
      currentQuantity: next.currentQuantity ?? currentQuantity,
      stockStatus: next.stockStatus ?? stockStatus,
      received: servedCount + next.servedCount,
    );
  }

  factory ProductHistoryResult.fromJson(Map<String, dynamic> json) {
    final entries = ((json['entries'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ProductHistoryEntry.fromJson)
        .toList(growable: false);
    final total = (json['total'] as num?)?.toInt();
    final offset = (json['offset'] as num?)?.toInt() ?? 0;
    return ProductHistoryResult(
      shopProductId: (json['shop_product_id'] as num?)?.toInt() ?? 0,
      entries: entries,
      total: total,
      offset: offset,
      limit: (json['limit'] as num?)?.toInt() ?? entries.length,
      // Trust the server's flag when present; otherwise derive it so an older
      // payload still reports pagination honestly.
      hasMore: json['has_more'] as bool? ??
          (total != null && offset + entries.length < total),
      currentQuantity: (json['current_quantity'] as num?)?.toInt(),
      stockStatus: json['stock_status'] as String?,
      received: entries.length,
    );
  }
}
