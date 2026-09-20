import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_providers.dart';
import '../../../core/state/system_state.dart';
import '../../products/data/products_snapshot_store.dart';
import '../../products/domain/product_models.dart';

/// Inventory data access for one authorized shop.
///
/// Ownership (repository rule): everything that reads or mutates the shop's
/// STOCK lives here — the overview (`GET /shops/{id}/inventory`), delta stock
/// adjustments, the per-product movement history and the low-stock threshold.
/// Product CRUD (creating / editing a listing) stays in [ProductRepository];
/// this file never creates or edits a listing.
abstract class InventoryRepository {
  /// The full shop inventory with the server's OWN summary counts
  /// (`view=list` also carries freshness + source per row).
  Future<InventoryOverview> fetchInventoryOverview(int shopId, String token);

  /// Delta stock adjustment with a full backend audit trail
  /// (`POST /shops/{shopId}/products/{productId}/stock-adjustments`).
  Future<StockAdjustmentResult> adjustStock(int shopId, int productId,
      Map<String, dynamic> payload, String token);

  /// Inventory history: movements, adjustments and price changes, newest
  /// first (`GET /shops/{shopId}/products/{productId}/history`).
  Future<ProductHistoryResult> fetchProductHistory(
      int shopId, int productId, String token);

  /// Change the quantity at which a listing is flagged LOW_STOCK
  /// (`PATCH /shops/{shopId}/products/{productId}/low-stock-threshold`).
  ///
  /// Returns the SERVER-derived stock state: the threshold decides whether the
  /// current quantity counts as LOW_STOCK, so the new status is computed
  /// server-side and must never be guessed here.
  Future<LowStockThresholdResult> updateLowStockThreshold(
      int shopId, int productId, int threshold, String token);

  /// Adjustment-only audit trail for one product
  /// (`GET /shops/{shopId}/products/{productId}/stock-adjustments`).
  Future<StockAdjustmentHistory> fetchStockAdjustments(
      int shopId, int productId, String token);

  /// Drops the device's offline inventory snapshot.
  ///
  /// Called on account switch/logout: cached stock belongs to the account
  /// that synced it and must never survive into the next session. This
  /// repository is the snapshot's only writer AND clearer — callers never
  /// touch the store directly.
  Future<void> clearOfflineSnapshot();
}

class ApiInventoryRepository implements InventoryRepository {
  ApiInventoryRepository(this._api, {ProductsSnapshotStore? snapshotStore})
      : _snapshots = snapshotStore;

  final ApiClient _api;

  /// Offline read-only fallback (null in tests that don't exercise it).
  final ProductsSnapshotStore? _snapshots;

  @override
  Future<InventoryOverview> fetchInventoryOverview(
      int shopId, String token) async {
    // `view=list` returns every item with last_updated + freshness_status +
    // source — plus the server's OWN summary counts. Reading those counts
    // instead of re-deriving them is what keeps a single source of truth for
    // the stock vocabulary; the app never keeps a second copy of it.
    try {
      final data = await _api.get(
        ApiEndpoints.inventory('$shopId'),
        query: const {'view': 'list'},
        token: token,
      ) as Map<String, dynamic>;
      // Best-effort offline snapshot: a REAL response is the only thing ever
      // stored, and storing must never break the live path.
      await _snapshots?.save('$shopId', data);
      if (data['summary'] != null) return InventoryOverview.fromJson(data);
      // Backend without a server summary: derive counts locally so the
      // dashboard still renders.
      return _inventoryOverviewFromData({
        'items': data['items'] ?? const [],
      });
    } on ApiException catch (e) {
      // Read-only offline access: when the last synced list is on the device,
      // serve it clearly marked instead of an empty error screen. Any other
      // failure (server error, permission…) is NOT cacheable — rethrow.
      if (e.systemState == SystemState.offline) {
        final snapshot = await _snapshots?.read('$shopId');
        if (snapshot != null) return InventoryOverview.fromSnapshot(snapshot);
      }
      rethrow;
    }
  }

  @override
  Future<StockAdjustmentResult> adjustStock(int shopId, int productId,
      Map<String, dynamic> payload, String token) async {
    final data = await _api.post(
      ApiEndpoints.stockAdjustments('$shopId', '$productId'),
      body: payload,
      token: token,
    ) as Map<String, dynamic>;
    return StockAdjustmentResult.fromJson(data);
  }

  @override
  Future<ProductHistoryResult> fetchProductHistory(
      int shopId, int productId, String token) async {
    final data = await _api.get(
      ApiEndpoints.productHistory('$shopId', '$productId'),
      token: token,
    ) as Map<String, dynamic>;
    return ProductHistoryResult.fromJson(data);
  }

  @override
  Future<LowStockThresholdResult> updateLowStockThreshold(
      int shopId, int productId, int threshold, String token) async {
    final data = await _api.patch(
      ApiEndpoints.lowStockThreshold('$shopId', '$productId'),
      body: {'low_stock_threshold': threshold},
      token: token,
    ) as Map<String, dynamic>;
    return LowStockThresholdResult.fromJson(data);
  }

  @override
  Future<StockAdjustmentHistory> fetchStockAdjustments(
      int shopId, int productId, String token) async {
    final data = await _api.get(
      ApiEndpoints.stockAdjustmentHistory('$shopId', '$productId'),
      token: token,
    ) as Map<String, dynamic>;
    return StockAdjustmentHistory.fromJson(data);
  }

  @override
  Future<void> clearOfflineSnapshot() async {
    // Store is optional (null in tests that never exercise offline mode).
    await _snapshots?.clearAll();
  }
}

/// Builds an [InventoryOverview] from a `view=list` response body that carries
/// no server summary.
///
/// This is the fallback path only. Classification goes through
/// [StockStateView] — the app's ONE stock-state mapping — so even a derived
/// count cannot drift from the vocabulary the rest of the app renders.
InventoryOverview _inventoryOverviewFromData(Map<String, dynamic> json) {
  final items = ((json['items'] as List<dynamic>?) ?? const [])
      .whereType<Map<String, dynamic>>()
      .map(ShopProductItem.fromJson)
      .toList(growable: false);
  var inStock = 0, lowStock = 0, outOfStock = 0, totalUnits = 0;
  for (final item in items) {
    totalUnits += item.quantity;
    final state = item.stockState;
    if (state.isOutOfStock) {
      outOfStock += 1;
    } else if (state.isLowStock) {
      lowStock += 1;
    } else if (state.isInStock) {
      inStock += 1;
    }
  }
  final summary = (
    total: items.length,
    active: items.where((i) => i.isActive && i.isAvailable).length,
    inStock: inStock,
    lowStock: lowStock,
    outOfStock: outOfStock,
    totalUnits: totalUnits,
  );
  return InventoryOverview(items: items, summary: summary);
}

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  return ApiInventoryRepository(
    ref.watch(apiClientProvider),
    snapshotStore: ref.watch(productsSnapshotStoreProvider),
  );
});
