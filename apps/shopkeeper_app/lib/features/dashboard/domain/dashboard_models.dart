import '../../shops/domain/shop_models.dart'
    show ShopCapabilities, SubscriptionInfo, VerificationInfo;

/// One product the backend flagged as needing attention
/// (LOW_STOCK / LIMITED_STOCK / OUT_OF_STOCK, sorted OUT_OF_STOCK first).
class NeedsAttentionItem {
  const NeedsAttentionItem({
    required this.shopProductId,
    required this.name,
    required this.quantity,
    required this.stockStatus,
  });

  final int shopProductId;
  final String name;
  final int quantity;
  final String stockStatus;

  bool get isOutOfStock => stockStatus == 'OUT_OF_STOCK';

  factory NeedsAttentionItem.fromJson(Map<String, dynamic> json) =>
      NeedsAttentionItem(
        shopProductId: (json['shop_product_id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? 'Unnamed',
        quantity: (json['quantity'] as num?)?.toInt() ?? 0,
        stockStatus: json['stock_status'] as String? ?? 'UNKNOWN',
      );
}

/// Aggregate product statistics from the dashboard payload.
class ProductStats {
  const ProductStats({
    required this.total,
    required this.active,
    required this.inactive,
    required this.inStock,
    required this.lowStock,
    required this.outOfStock,
    required this.totalUnits,
    this.needsAttention = const [],
  });

  final int total;
  final int active;
  final int inactive;
  final int inStock;
  final int lowStock;
  final int outOfStock;
  final int totalUnits;

  /// Up to 10 named products (server-sorted, OUT_OF_STOCK first).
  final List<NeedsAttentionItem> needsAttention;

  factory ProductStats.fromJson(Map<String, dynamic> json) => ProductStats(
        total: (json['total'] as num?)?.toInt() ?? 0,
        active: (json['active'] as num?)?.toInt() ?? 0,
        inactive: (json['inactive'] as num?)?.toInt() ?? 0,
        inStock: (json['in_stock'] as num?)?.toInt() ?? 0,
        lowStock: (json['low_stock'] as num?)?.toInt() ?? 0,
        outOfStock: (json['out_of_stock'] as num?)?.toInt() ?? 0,
        totalUnits: (json['total_units'] as num?)?.toInt() ?? 0,
        needsAttention:
            ((json['needs_attention'] as List<dynamic>?) ?? const [])
                .whereType<Map<String, dynamic>>()
                .map(NeedsAttentionItem.fromJson)
                .toList(growable: false),
      );
}

class RecentUpdate {
  const RecentUpdate({required this.type, required this.label, this.quantity});

  final String type;
  final String label;
  final int? quantity;

  factory RecentUpdate.fromJson(Map<String, dynamic> json) => RecentUpdate(
        type: json['type'] as String? ?? 'update',
        label: json['label'] as String? ?? '',
        quantity: (json['quantity'] as num?)?.toInt(),
      );
}

class OffersSummary {
  const OffersSummary({
    required this.total,
    required this.active,
    required this.draft,
  });

  final int total;
  final int active;
  final int draft;

  factory OffersSummary.fromJson(Map<String, dynamic> json) => OffersSummary(
        total: (json['total'] as num?)?.toInt() ?? 0,
        active: (json['active'] as num?)?.toInt() ?? 0,
        draft: (json['draft'] as num?)?.toInt() ?? 0,
      );
}

/// Non-fatal "needs attention" signals for the dashboard priority card.
///
/// Every field degrades independently: a failed lookup simply hides the
/// corresponding priority row — it never blocks the dashboard itself.
class DashboardAlerts {
  const DashboardAlerts({
    this.failedImportName,
    this.failedImportRows = 0,
    this.staleCount = 0,
    this.unreadNotifications = 0,
  });

  /// Filename of the most recent import job that failed or completed with
  /// row errors (from the import-jobs listing, not fabricated client-side).
  final String? failedImportName;

  /// Rows the failed/partial import could not apply.
  final int failedImportRows;

  /// Products whose inventory data the backend flagged as STALE.
  final int staleCount;

  /// Unread notifications for this shop.
  final int unreadNotifications;

  bool get hasFailedImport => failedImportName != null;

  /// True when none of the priority rows has data — the card stays hidden.
  bool get isEmpty =>
      !hasFailedImport && staleCount == 0 && unreadNotifications == 0;
}

/// Full operational dashboard payload.
class DashboardData {
  const DashboardData({
    required this.shopName,
    required this.shopStatus,
    required this.isVerified,
    required this.verification,
    required this.subscription,
    this.capabilities = const ShopCapabilities(),
    required this.products,
    required this.recentUpdates,
    required this.offers,
  });

  final String shopName;
  final String shopStatus;
  final bool isVerified;
  final VerificationInfo verification;
  final SubscriptionInfo subscription;

  /// Backend-driven feature flags (spec section 103). Absent on old
  /// payloads -> permissive default, never a lock-out.
  final ShopCapabilities capabilities;
  final ProductStats products;
  final List<RecentUpdate> recentUpdates;
  final OffersSummary offers;

  factory DashboardData.fromJson(Map<String, dynamic> json) {
    final shop = json['shop'] as Map<String, dynamic>? ?? const {};
    return DashboardData(
      shopName: shop['name'] as String? ?? '',
      shopStatus: shop['status'] as String? ?? '',
      isVerified: shop['is_verified'] as bool? ?? false,
      verification: VerificationInfo.fromJson(
          json['verification'] as Map<String, dynamic>?),
      subscription: SubscriptionInfo.fromJson(
          json['subscription'] as Map<String, dynamic>?),
      capabilities: ShopCapabilities.fromJson(
          json['capabilities'] as Map<String, dynamic>?),
      products: ProductStats.fromJson(
          json['products'] as Map<String, dynamic>? ?? const {}),
      recentUpdates:
          ((json['recent_updates'] as List<dynamic>?) ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(RecentUpdate.fromJson)
              .toList(growable: false),
      offers: OffersSummary.fromJson(
          json['offers'] as Map<String, dynamic>? ?? const {}),
    );
  }
}
