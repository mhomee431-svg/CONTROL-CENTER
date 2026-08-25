import '../../shops/domain/shop_models.dart';

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
  });

  final int total;
  final int active;
  final int inactive;
  final int inStock;
  final int lowStock;
  final int outOfStock;
  final int totalUnits;

  factory ProductStats.fromJson(Map<String, dynamic> json) => ProductStats(
        total: (json['total'] as num?)?.toInt() ?? 0,
        active: (json['active'] as num?)?.toInt() ?? 0,
        inactive: (json['inactive'] as num?)?.toInt() ?? 0,
        inStock: (json['in_stock'] as num?)?.toInt() ?? 0,
        lowStock: (json['low_stock'] as num?)?.toInt() ?? 0,
        outOfStock: (json['out_of_stock'] as num?)?.toInt() ?? 0,
        totalUnits: (json['total_units'] as num?)?.toInt() ?? 0,
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

/// Full operational dashboard payload.
class DashboardData {
  const DashboardData({
    required this.shopName,
    required this.shopStatus,
    required this.isVerified,
    required this.verification,
    required this.subscription,
    required this.products,
    required this.recentUpdates,
    required this.offers,
  });

  final String shopName;
  final String shopStatus;
  final bool isVerified;
  final VerificationInfo verification;
  final SubscriptionInfo subscription;
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
