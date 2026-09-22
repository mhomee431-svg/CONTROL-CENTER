import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/token_store.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../../inventory/data/inventory_repository.dart';
import '../../data/product_repository.dart';
import '../../domain/product_models.dart';

enum ProductsStatus { loading, ready, accessDenied, error }

/// The catalog's DATA state: the rows, the server's summary counts and the
/// lifecycle of the last read/write.
///
/// What this state covers, and where each facet lives:
///   * list          — [items] (the whole catalog in one `view=list` response)
///   * loading/error — [status] + [message] (`accessDenied` is its own status,
///                     because "you may not see this shop" is not a retryable
///                     failure)
///   * detail        — [itemById]: Product Details is DERIVED from these rows,
///                     never fetched a second time, so opening it cannot blank
///                     or re-sort the list behind it
///   * create / edit / deactivate — `createProduct` / `saveEdits` /
///                     `setAvailability` on [ProductsController], each of which
///                     swaps the server's own row back into [items]
///   * search / filter / sort / pagination — the products LIST's own view state
///                     (`ProductsListState`), kept per-screen so one screen's
///                     filter can never narrow another's
class ProductsState {
  const ProductsState({
    required this.status,
    this.items = const [],
    this.summary,
    this.message,
    this.fromCache = false,
  });

  final ProductsStatus status;
  final List<ShopProductItem> items;
  final InventorySummary? summary;
  final String? message;

  /// True when [items] were rebuilt from the device's offline snapshot rather
  /// than a live response (see `ProductsSnapshotStore`).
  final bool fromCache;

  /// The LIVE row for [id] — or null once it has left the catalog.
  ///
  /// A details view resolves its row through this instead of rendering the row
  /// it was tapped with: after an edit or a stock adjustment the controller
  /// swaps the row in place, so the open view refreshes itself, and a row that
  /// was removed can be reported as gone rather than shown from a stale copy.
  ShopProductItem? itemById(int id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  factory ProductsState.loading({ProductsState? from}) => ProductsState(
        status: ProductsStatus.loading,
        items: from?.items ?? const [],
        summary: from?.summary,
        fromCache: from?.fromCache ?? false,
      );
}

final productsControllerProvider =
    NotifierProvider<ProductsController, ProductsState>(ProductsController.new);

/// Result of a delta stock update. [error] holds the readable backend
/// message when [ok] is false (negative stock, invalid numbers, permission,
/// offline) so the sheet can show it verbatim.
class StockAdjustOutcome {
  const StockAdjustOutcome({required this.ok, this.result, this.error});

  final bool ok;
  final StockAdjustmentResult? result;
  final String? error;
}

/// Result of loading a product's audit trail.
class ProductHistoryLoad {
  const ProductHistoryLoad({this.history, this.error});

  final ProductHistoryResult? history;
  final String? error;

  bool get ok => history != null;
}

class ProductsController extends Notifier<ProductsState> {
  @override
  ProductsState build() => ProductsState.loading();

  ProductRepository get _repo => ref.read(productRepositoryProvider);

  /// Stock reads/writes (overview, adjustments, history, thresholds) belong to
  /// the inventory repository; product CRUD stays in [_repo].
  InventoryRepository get _inventoryRepo =>
      ref.read(inventoryRepositoryProvider);

  int? get _shopId => ref.read(selectedShopProvider)?.id;

  Future<void> load() async {
    final shopId = _shopId;
    if (shopId == null) {
      state = const ProductsState(
          status: ProductsStatus.error, message: 'No shop selected');
      return;
    }
    state = ProductsState.loading(from: state);
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) throw const ApiException(message: 'Not signed in');
      final overview = await _inventoryRepo.fetchInventoryOverview(shopId, token);
      state = ProductsState(
        status: ProductsStatus.ready,
        items: overview.items,
        summary: overview.summary,
        fromCache: overview.fromCache,
      );
    } on ApiException catch (e) {
      state = ProductsState(
        status: e.isForbidden ? ProductsStatus.accessDenied : ProductsStatus.error,
        message: e.message,
      );
    } catch (_) {
      state = const ProductsState(
          status: ProductsStatus.error,
          message: 'Could not load inventory.');
    }
  }

  /// Clears ALL cached inventory data (called on logout) so the previous
  /// account's products never survive into the next session — the in-memory
  /// state AND the device's offline snapshot store (cleared through the
  /// repository that owns it).
  void reset() {
    state = ProductsState.loading();
    unawaited(_inventoryRepo.clearOfflineSnapshot());
  }

  Future<bool> setAvailability(int productId, bool available) async {
    final updated = await _patch(productId, {'is_available': available});
    return updated != null;
  }

  /// Applies a **delta** stock change through the backend audit-trail
  /// endpoint (req 25) and swaps in the server-computed quantity/state — the
  /// backend stays authoritative; the client never guesses the new stock.
  ///
  /// Returns [StockAdjustOutcome]: on failure [StockAdjustOutcome.error]
  /// carries the readable backend message (e.g. negative inventory).
  Future<StockAdjustOutcome> adjustStock({
    required int productId,
    required int delta,
    String adjustmentType = 'CORRECTION',
    String? reason,
  }) async {
    final shopId = _shopId;
    if (shopId == null) {
      return const StockAdjustOutcome(
          ok: false, error: 'No shop selected');
    }
    if (delta == 0) {
      // Mirrors the backend rule — never round-trip a no-op.
      return const StockAdjustOutcome(
          ok: false, error: 'Quantity change cannot be zero');
    }
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) throw const ApiException(message: 'Not signed in');
      final result = await _inventoryRepo.adjustStock(shopId, productId, {
        'adjustment_type': adjustmentType,
        'quantity_adjustment': delta,
        'reason': ?reason,
      }, token);
      // Trust the server's post-update numbers, not the client's arithmetic.
      state = ProductsState(
        status: state.status == ProductsStatus.accessDenied
            ? ProductsStatus.accessDenied
            : ProductsStatus.ready,
        items: [
          for (final item in state.items)
            if (item.id == productId)
              item.copyWith(
                quantity: result.newQuantity,
                stockStatus: result.stockStatus,
                isAvailable: result.newQuantity > 0,
                lastUpdated: result.lastInventoryUpdate ?? DateTime.now(),
                source: 'MANUAL',
                updatedBy: item.updatedBy,
              )
            else
              item,
        ],
        summary: state.summary,
      );
      return StockAdjustOutcome(ok: true, result: result);
    } on ApiException catch (e) {
      final message = e.isForbidden
          ? 'You do not have permission to update stock for this shop.'
          : (e.statusCode == 404
              ? 'This product is no longer in your inventory.'
              : e.message);
      state = ProductsState(
        status: e.isForbidden
            ? ProductsStatus.accessDenied
            : (state.status == ProductsStatus.accessDenied
                ? ProductsStatus.accessDenied
                : ProductsStatus.ready),
        items: state.items,
        summary: state.summary,
        message: message,
      );
      return StockAdjustOutcome(ok: false, error: message);
    } catch (_) {
      const message = 'Could not update stock. Please retry.';
      state = ProductsState(
        status: ProductsStatus.ready,
        items: state.items,
        summary: state.summary,
        message: message,
      );
      return const StockAdjustOutcome(ok: false, error: message);
    }
  }

  /// Loads ONE PAGE of a product's audit trail (movements / adjustments /
  /// price changes). Never throws — failures surface as a readable message so
  /// the history sheet can render an inline error instead of dying.
  ///
  /// [offset] is the caller's page position: 0 fetches the newest page, and the
  /// history screens pass the offset the previous page ended at
  /// ([ProductHistoryResult.nextOffset]) to append the next one. The server
  /// pages this history, so a long-lived product never ships its whole audit
  /// trail in a single response.
  Future<ProductHistoryLoad> loadHistory(int productId, {int offset = 0}) async {
    final shopId = _shopId;
    if (shopId == null) {
      return const ProductHistoryLoad(error: 'No shop selected');
    }
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) throw const ApiException(message: 'Not signed in');
      final history = await _inventoryRepo.fetchProductHistory(
        shopId,
        productId,
        token,
        offset: offset,
      );
      return ProductHistoryLoad(history: history);
    } on ApiException catch (e) {
      return ProductHistoryLoad(
        error: e.isForbidden
            ? 'You do not have permission to view this history.'
            : e.message,
      );
    } catch (_) {
      return const ProductHistoryLoad(error: 'Could not load history.');
    }
  }

  /// Loads the NEXT page of a product's audit trail and stitches it onto
  /// [current] — the shared append rule, so the stock history and the price
  /// history page through identical logic.
  ///
  /// Returns [current] unchanged (with the reason) when the page could not be
  /// fetched: a failed page must never empty the history already on screen.
  Future<ProductHistoryLoad> loadMoreHistory(
    int productId,
    ProductHistoryResult current,
  ) async {
    final next = await loadHistory(productId, offset: current.nextOffset);
    if (!next.ok) {
      return ProductHistoryLoad(history: current, error: next.error);
    }
    return ProductHistoryLoad(history: current.append(next.history!));
  }

  /// Clears a one-off error message after it has been surfaced.
  void clearTransientMessage() {
    if (state.message != null) {
      state = ProductsState(
        status: state.status,
        items: state.items,
        summary: state.summary,
      );
    }
  }

  Future<bool> saveEdits({
    required int productId,
    double? price,
    double? mrp,
    int? quantity,
    int? lowStockThreshold,
    String? imageKey,
  }) async {
    final fields = <String, dynamic>{
      'price': ?price,
      'mrp': ?mrp,
      'quantity': ?quantity,
      'low_stock_threshold': ?lowStockThreshold,
      'image_key': ?imageKey,
    };
    return await _patch(productId, fields) != null;
  }

  /// Applies a PATCH and swaps the item in place with the server response.
  Future<ShopProductItem?> _patch(
      int productId, Map<String, dynamic> fields) async {
    final shopId = _shopId;
    if (shopId == null) return null;
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) throw const ApiException(message: 'Not signed in');
      final updated =
          await _repo.updateProduct(shopId, productId, fields, token);
      state = ProductsState(
        status: state.status == ProductsStatus.accessDenied
            ? ProductsStatus.accessDenied
            : ProductsStatus.ready,
        items: [
          for (final item in state.items)
            if (item.id == productId) updated else item,
        ],
        summary: state.summary,
      );
      return updated;
    } on ApiException catch (e) {
      state = ProductsState(
        status: e.isForbidden ? ProductsStatus.accessDenied : ProductsStatus.ready,
        items: state.items,
        summary: state.summary,
        message: e.message,
      );
      return null;
    } catch (_) {
      state = ProductsState(
        status: ProductsStatus.ready,
        items: state.items,
        summary: state.summary,
        message: 'Update failed. Please retry.',
      );
      return null;
    }
  }

  Future<bool> createProduct({
    required String name,
    required double price,
    double? mrp,
    String? unit,
    String? sku,
    String? brand,
    String? description,
    String? imageKey,
    bool isAvailable = true,
    int quantity = 0,
    int lowStockThreshold = 5,
    required bool publish,
    int? categoryId,
    int? subcategoryId,
    String? barcode,
  }) async {
    final shopId = _shopId;
    if (shopId == null) return false;
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) throw const ApiException(message: 'Not signed in');
      // Payload mirrors the backend ShopkeeperProductCreate schema exactly.
      // The MANUAL barcode here becomes the master's primary identifier; the
      // scanner flow (POST /scan-barcode) stays the resolution path at scan
      // time — one catalog fact, two ways to reach it.
      final created = await _repo.createProduct(shopId, {
        'name': name,
        'price': price,
        'mrp': ?mrp,
        if (unit != null && unit.isNotEmpty) 'unit': unit,
        if (sku != null && sku.isNotEmpty) 'sku': sku,
        if (brand != null && brand.isNotEmpty) 'brand_name': brand,
        if (description != null && description.isNotEmpty)
          'description': description,
        'image_key': ?imageKey,
        'is_available': isAvailable,
        'quantity': quantity,
        'low_stock_threshold': lowStockThreshold,
        'publish': publish,
        'category_id': ?categoryId,
        'subcategory_id': ?subcategoryId,
        if (barcode != null && barcode.isNotEmpty) 'barcode': barcode,
      }, token);
      state = ProductsState(
        status: ProductsStatus.ready,
        items: [created, ...state.items],
        summary: state.summary,
      );
      return true;
    } on ApiException catch (e) {
      state = ProductsState(
          status: ProductsStatus.ready,
          items: state.items,
          summary: state.summary,
          message: e.message);
      return false;
    } catch (_) {
      state = ProductsState(
          status: ProductsStatus.ready,
          items: state.items,
          summary: state.summary,
          message: 'Could not create the product.');
      return false;
    }
  }
}
