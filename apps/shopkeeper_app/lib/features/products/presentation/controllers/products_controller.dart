import '../../../../../core/errors/app_message_code.dart';
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

  /// Bumped by every [load] / [reset]: a server-search response captured an
  /// earlier generation (or an earlier shop) must never merge into the
  /// catalog that is on screen now.
  int _generation = 0;

  /// The last settled query a server search was (or would have been) run for.
  /// Set BEFORE the request goes out, so the at-most-once rule holds even if
  /// the screen schedules the same query twice. Cleared by [load] / [reset]:
  /// a fresh catalog may re-ask the server the same question.
  String? _serverAnsweredFor;

  /// Monotonic sequence for stock WRITES, plus the newest one started per
  /// product.
  ///
  /// The read paths are generation-guarded, but a write can also race ITSELF:
  /// the shopkeeper saves +5, then saves +3 before the first answer lands, and
  /// the second response can arrive first. Without this guard the older,
  /// already-superseded answer lands last and silently rolls the row back to a
  /// quantity the shopkeeper has moved past.
  int _writeSeq = 0;
  final Map<int, int> _latestWrite = <int, int>{};

  /// True when [seq] is still the newest stock write for [productId] — i.e.
  /// when this response is one the catalog should actually adopt.
  bool _isLatestWrite(int productId, int seq) =>
      _latestWrite[productId] == seq;

  /// Minimum submitted length worth a server round-trip — single letters are
  /// half-typed drafts (same rule as the recent-searches history).
  static const int _minServerQueryLength = 2;

  /// The backend caps `search` at 120 chars (`Query(max_length=120)`); a
  /// longer term would be rejected with a 422, so it is never sent.
  static const int _maxServerQueryLength = 120;

  Future<void> load() async {
    _generation++;
    _serverAnsweredFor = null;
    final shopId = _shopId;
    if (shopId == null) {
      state = const ProductsState(
          status: ProductsStatus.error, message: 'No shop selected');
      return;
    }
    state = ProductsState.loading(from: state);
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) throw ApiException.localized(AppMessageCode.notSignedIn);
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

  bool _refreshInFlight = false;

  /// Silent re-fetch used by pull-to-refresh: the list keeps showing the
  /// current rows while fresh ones load, and a failure keeps the current view
  /// instead of throwing an error over working data. Re-entrant calls are
  /// dropped, never queued.
  ///
  /// [load] stays the LOUD path (spinner, error state) for the first load and
  /// for Retry buttons; this is the one for a gesture whose progress the
  /// shopkeeper already sees in the pull indicator.
  Future<void> refresh() async {
    if (_refreshInFlight) return;
    final shopId = _shopId;
    if (shopId == null) return;
    _refreshInFlight = true;
    // A refresh replaces the whole catalog: a server-search response from the
    // previous generation must not merge into the new rows, and the same
    // query may be asked again against the fresh catalog.
    _generation++;
    _serverAnsweredFor = null;
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      // Signed out mid-flight → keep the current view; logout resets state.
      if (token == null) return;
      final overview =
          await _inventoryRepo.fetchInventoryOverview(shopId, token);
      // The shop switched while the request was in flight: this answer
      // belongs to a catalog that is no longer on screen.
      if (shopId != _shopId) return;
      state = ProductsState(
        status: ProductsStatus.ready,
        items: overview.items,
        summary: overview.summary,
        fromCache: overview.fromCache,
      );
    } catch (_) {
      // Silent: a failed pull keeps the rows on screen — the next pull tries
      // again.
    } finally {
      _refreshInFlight = false;
    }
  }

  /// SERVER search — the products list's stale-catalog recovery path.
  ///
  /// The local predicate filters the already-loaded catalog on every settled
  /// query; this asks the backend (`view=list&search=`) ONLY when that catalog
  /// could not answer — the screen calls it with zero local matches. Because
  /// the server matches a subset of the local fields (name / sku), any row it
  /// returns that we lack is a row the payload was missing entirely (created
  /// on another device, or after the last load); matching rows already on
  /// screen are simply not re-sent.
  ///
  /// Contract:
  ///   * at MOST ONCE per settled query — [_serverAnsweredFor] is marked
  ///     before the request leaves, so a rebuild (or a keystroke upstream of
  ///     the field's debounce) can never queue a second call. This is what
  ///     keeps "no API call for every keystroke" true.
  ///   * only for queries inside the backend's length bounds (2..120).
  ///   * fail-soft — any error (offline, 4xx/5xx, no token) leaves the local
  ///     state untouched: the shopkeeper keeps the honest "no match" result
  ///     and a pull-to-refresh re-arms the search.
  ///   * generation-guarded — a response that lands after a reload or a shop
  ///     switch is dropped, so another shop's rows can never leak in.
  ///   * merged BY ID into the catalog — the rows are genuine listings, so
  ///     the counter, the filters, the sort and paging keep working on them;
  ///     the summary chips stay as-loaded until the next refresh recomputes
  ///     them (they were already stale — that is why the row was missing).
  Future<void> serverSearch(String raw) async {
    final query = raw.trim();
    if (query.length < _minServerQueryLength ||
        query.length > _maxServerQueryLength) {
      return;
    }
    // Synchronous dedupe: callers may schedule this twice before the first
    // microtask runs; only the first scheduling of a given query proceeds.
    if (query == _serverAnsweredFor) return;
    _serverAnsweredFor = query;

    final shopId = _shopId;
    if (shopId == null) return;
    final generation = _generation;
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) return;
      final found = await _inventoryRepo.searchInventoryList(
          shopId, token, query);
      // A reload or shop switch while the request was in flight: this answer
      // belongs to a catalog that is no longer on screen.
      if (generation != _generation || shopId != _shopId) return;
      if (state.status != ProductsStatus.ready) return;
      if (found.isEmpty) return;
      final known = <int>{for (final item in state.items) item.id};
      final additions = found
          .where((item) => !known.contains(item.id))
          .toList(growable: false);
      if (additions.isEmpty) return;
      state = ProductsState(
        status: state.status,
        items: [...state.items, ...additions],
        summary: state.summary,
        message: state.message,
        fromCache: state.fromCache,
      );
    } catch (_) {
      // Best-effort: the local no-match view already rendered and stays.
    }
  }

  /// Clears ALL cached inventory data (called on logout) so the previous
  /// account's products never survive into the next session — the in-memory
  /// state AND the device's offline snapshot store (cleared through the
  /// repository that owns it).
  void reset() {
    _generation++;
    _serverAnsweredFor = null;
    // An in-flight write from the previous session must not claim a slot in
    // the next account's catalog when it lands.
    _latestWrite.clear();
    state = ProductsState.loading();
    unawaited(_inventoryRepo.clearOfflineSnapshot());
  }

  Future<bool> setAvailability(int productId, bool available) async {
    final updated = await _patch(productId, {'is_available': available});
    return updated != null;
  }

  /// Deactivate or re-activate a LISTING (spec §74 / §75) — never a hard delete.
  ///
  /// The backend approves exactly ONE semantic for withdrawing a listing:
  /// `PATCH /shops/{id}/products/{pid}` with `{"status": ...}`. `DISCONTINUED`
  /// hides the listing from customers while leaving its price and inventory
  /// history intact (the model carries a `SoftDeleteMixin`, so the row stays
  /// queryable for reports) — which is precisely why the app offers deactivate
  /// and deliberately does not offer delete, per §75.
  ///
  /// Deliberately NOT bundled with `is_available`: availability is a visibility
  /// switch the shopkeeper toggles freely, whereas this is the lifecycle
  /// decision the confirmation dialog is asking about. Sending both would make
  /// one reversible action silently perform the other.
  ///
  /// Returns false and leaves the catalog untouched when the write is refused —
  /// [ProductsState.message] carries the backend's own wording, so the calling
  /// sheet can report it and keep the shopkeeper's place.
  Future<bool> setListingStatus(
      int productId, ListingStateView listing) async {
    final updated = await _patch(productId, {'status': listing.value});
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
    // Claim this product's write slot BEFORE the request goes out, so a second
    // save started before this one answers can supersede it.
    final seq = ++_writeSeq;
    _latestWrite[productId] = seq;
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) throw ApiException.localized(AppMessageCode.notSignedIn);
      final result = await _inventoryRepo.adjustStock(shopId, productId, {
        'adjustment_type': adjustmentType,
        'quantity_adjustment': delta,
        'reason': ?reason,
      }, token);
      // The write itself SUCCEEDED — it is only stale. Reporting it as an
      // error would be a lie, but repainting the row would roll the quantity
      // back behind a newer edit, so the catalog keeps the newer answer.
      if (!_isLatestWrite(productId, seq) || shopId != _shopId) {
        return StockAdjustOutcome(ok: true, result: result);
      }
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
                // A manual adjustment IS the freshest data the platform holds,
                // so the row must stop reading "Stale - needs a refresh" the
                // moment the shopkeeper fixes it by hand. The server reaches the
                // same tier (`compute_freshness(now, MANUAL)` →
                // RECENTLY_UPDATED) but does not send it on this response, and
                // the client is not guessing here: it just performed the write.
                freshnessStatus: 'RECENTLY_UPDATED',
                updatedBy: item.updatedBy,
              )
            else
              item,
        ],
        summary: state.summary,
      );
      return StockAdjustOutcome(ok: true, result: result);
    } on ApiException catch (e) {
      // A plan refusal explains itself ("…Upgrade to unlock this feature") —
      // only a plain association denial gets the generic permission copy.
      final message = e.isEntitlementDenied
          ? e.message
          : e.isForbidden
              ? 'You do not have permission to update stock for this shop.'
              : (e.statusCode == 404
                  ? 'This product is no longer in your inventory.'
                  : e.message);
      // A superseded write must not paint its error over a newer one that
      // already landed: the row on screen is the newer truth.
      if (_isLatestWrite(productId, seq) && shopId == _shopId) {
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
      }
      return StockAdjustOutcome(ok: false, error: message);
    } catch (_) {
      const message = 'Could not update stock. Please retry.';
      if (_isLatestWrite(productId, seq) && shopId == _shopId) {
        state = ProductsState(
          status: ProductsStatus.ready,
          items: state.items,
          summary: state.summary,
          message: message,
        );
      }
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
      if (token == null) throw ApiException.localized(AppMessageCode.notSignedIn);
      final history = await _inventoryRepo.fetchProductHistory(
        shopId,
        productId,
        token,
        offset: offset,
      );
      return ProductHistoryLoad(history: history);
    } on ApiException catch (e) {
      // Entitlement refusals keep the server's upgrade copy; a plain denial
      // gets the module's own permission wording.
      return ProductHistoryLoad(
        error: e.isEntitlementDenied
            ? e.message
            : e.isForbidden
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
    bool removeImage = false,
  }) async {
    final fields = <String, dynamic>{
      'price': ?price,
      'mrp': ?mrp,
      'quantity': ?quantity,
      'low_stock_threshold': ?lowStockThreshold,
      'image_key': ?imageKey,
      // Removal has to be explicit. `image_key: null` cannot express it: the
      // `?imageKey` spread above drops the key entirely, which the server reads
      // as "leave the photo alone" rather than "detach it".
      if (removeImage) 'remove_image': true,
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
      if (token == null) throw ApiException.localized(AppMessageCode.notSignedIn);
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
      if (token == null) throw ApiException.localized(AppMessageCode.notSignedIn);
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
