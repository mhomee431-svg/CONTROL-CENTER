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
      );

  ShopProductItem copyWith({
    bool? isAvailable,
    int? quantity,
    String? stockStatus,
    double? price,
    String? freshnessStatus,
    DateTime? lastUpdated,
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
