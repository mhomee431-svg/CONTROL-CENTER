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

  bool get isOutOfStock => stockStatus == 'OUT_OF_STOCK';
  bool get isLowStock => stockStatus == 'LOW_STOCK';

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
      );

  ShopProductItem copyWith({
    bool? isAvailable,
    int? quantity,
    String? stockStatus,
    double? price,
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
        status: status,
        price: price ?? this.price,
        mrp: mrp,
        isActive: isActive,
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
});

InventorySummary inventorySummaryFromJson(Map<String, dynamic> json) => (
      total: (json['total'] as num?)?.toInt() ?? 0,
      active: (json['active'] as num?)?.toInt() ?? 0,
      inStock: (json['in_stock'] as num?)?.toInt() ?? 0,
      lowStock: (json['low_stock'] as num?)?.toInt() ?? 0,
      outOfStock: (json['out_of_stock'] as num?)?.toInt() ?? 0,
      totalUnits: (json['total_units'] as num?)?.toInt() ?? 0,
    );

class InventoryOverview {
  const InventoryOverview({required this.items, required this.summary});

  final List<ShopProductItem> items;
  final InventorySummary summary;

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
}
/// Server-authoritative inventory stock state (req 21/25).
///
/// The backend owns the vocabulary and sends it verbatim
/// (`IN_STOCK` / `LOW_STOCK` / `OUT_OF_STOCK` / `UNKNOWN` /
/// `DISCONTINUOUS`). The client NEVER re-declares its own enum duplicate —
/// it only maps the received value to one shared display label, so a brand
/// new server state still renders (humanised) instead of throwing on an
/// unknown enum constant. Every screen reads stock state through this one
/// helper, so the mapping can never drift between features.
class StockStateView {
  const StockStateView._(this.value, this.label);

  /// Raw server value this view was derived from.
  final String value;

  /// Shopkeeper-facing label.
  final String label;

  static const inStock = StockStateView._('IN_STOCK', 'In stock');
  static const lowStock = StockStateView._('LOW_STOCK', 'Low stock');
  static const outOfStock = StockStateView._('OUT_OF_STOCK', 'Out of stock');
  static const unknown = StockStateView._('UNKNOWN', 'Unknown');
  static const discontinued =
      StockStateView._('DISCONTINUOUS', 'Discontinued');

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
    'DISCONTINUOUS': discontinued,
    'DISCONTINUED': discontinued,
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
  bool get isDiscontinued => value == 'DISCONTINUOUS';
  bool get isUnknown => value == 'UNKNOWN';
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
  });

  final int shopProductId;
  final int previousQuantity;
  final int quantityAdjustment;
  final int newQuantity;

  /// Server stock state string after the update.
  final String stockStatus;
  final String? adjustmentType;
  final DateTime? lastInventoryUpdate;

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
      );
}

/// Combined audit trail for one shop product (newest first, server-sorted).
class ProductHistoryResult {
  const ProductHistoryResult({
    required this.shopProductId,
    required this.entries,
  });

  final int shopProductId;
  final List<ProductHistoryEntry> entries;

  /// Parsed entry count.
  int get count => entries.length;

  factory ProductHistoryResult.fromJson(Map<String, dynamic> json) =>
      ProductHistoryResult(
        shopProductId: (json['shop_product_id'] as num?)?.toInt() ?? 0,
        entries: ((json['entries'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ProductHistoryEntry.fromJson)
            .toList(growable: false),
      );
}
