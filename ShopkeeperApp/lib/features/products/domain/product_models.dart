/// A product listed under the shopkeeper's own shop
/// (shop_products + inventory projection).
class ShopProductItem {
  const ShopProductItem({
    required this.id,
    required this.name,
    required this.status,
    required this.price,
    this.mrp,
    this.sku,
    required this.isActive,
    required this.isAvailable,
    required this.quantity,
    required this.stockStatus,
  });

  final int id;
  final String name;
  final String? sku;
  final String status;
  final double price;
  final double? mrp;
  final bool isActive;
  final bool isAvailable;
  final int quantity;
  final String stockStatus;

  bool get isOutOfStock => stockStatus == 'OUT_OF_STOCK';
  bool get isLowStock => stockStatus == 'LOW_STOCK';

  factory ShopProductItem.fromJson(Map<String, dynamic> json) =>
      ShopProductItem(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? 'Unnamed',
        sku: json['sku'] as String?,
        status: json['status'] as String? ?? 'ACTIVE',
        price: (json['price'] as num?)?.toDouble() ?? 0,
        mrp: (json['mrp'] as num?)?.toDouble(),
        isActive: json['is_active'] as bool? ?? false,
        isAvailable: json['is_available'] as bool? ?? false,
        quantity: (json['quantity'] as num?)?.toInt() ?? 0,
        stockStatus: json['stock_status'] as String? ?? 'UNKNOWN',
      );

  ShopProductItem copyWith({
    bool? isAvailable,
    int? quantity,
    String? stockStatus,
    double? price,
  }) =>
      ShopProductItem(
        id: id,
        name: name,
        sku: sku,
        status: status,
        price: price ?? this.price,
        mrp: mrp,
        isActive: isActive,
        isAvailable: isAvailable ?? this.isAvailable,
        quantity: quantity ?? this.quantity,
        stockStatus: stockStatus ?? this.stockStatus,
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
