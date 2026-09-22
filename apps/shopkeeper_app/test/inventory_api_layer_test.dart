import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_endpoints.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/data/inventory_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_models.dart';

import 'fakes.dart';

/// The inventory data layer must not keep a second copy of the stock
/// vocabulary: the shop summary comes from the server, and a low-stock
/// threshold change returns the server-derived state.
void main() {
  group('endpoint paths', () {
    test('low-stock threshold hangs off the product resource', () {
      expect(
        ApiEndpoints.lowStockThreshold('10', '77'),
        '/api/v1/shopkeeper/shops/10/products/77/low-stock-threshold',
      );
    });

    test('adjustment history hangs off the product resource', () {
      expect(
        ApiEndpoints.stockAdjustmentHistory('10', '77'),
        '/api/v1/shopkeeper/shops/10/products/77/stock-adjustments',
      );
    });
  });

  group('fetchInventoryOverview uses the server summary', () {
    /// A discontinued listing with 11 units left: a client that re-derives
    /// counts from `stock_status` would call this "in stock" — the server
    /// says it is not.
    Map<String, dynamic> body({required bool withSummary}) {
      final payload = <String, dynamic>{
        'count': 1,
        'items': [
          {
            'id': 132,
            'shop_id': 10,
            'name': 'Old Biscuits',
            'status': 'DISCONTINUED',
            'stock_status': 'IN_STOCK',
            'quantity': 11,
            'price': 70,
            'is_active': true,
            'is_available': false,
          },
        ],
      };
      if (withSummary) {
        payload['summary'] = {
          'total': 1,
          'active': 0,
          'inactive': 0,
          'discontinued': 1,
          'in_stock': 0,
          'low_stock': 0,
          'out_of_stock': 0,
          'unknown': 0,
          'total_units': 11,
        };
      }
      return payload;
    }

    test('server counts win — even against a misleading stock_status', () {
      final repo = ApiInventoryRepository(
        FakeApiClient(response: body(withSummary: true)),
      );
      return repo.fetchInventoryOverview(10, 'tok').then((overview) {
        expect(overview.summary.total, 1);
        // The server, not the client, decided this listing is not in stock.
        expect(overview.summary.inStock, 0);
        expect(overview.items.single.isDiscontinued, isTrue);
      });
    });

    test('falls back to derived counts when the server ships no summary', () {
      final repo = ApiInventoryRepository(
        FakeApiClient(response: body(withSummary: false)),
      );
      return repo.fetchInventoryOverview(10, 'tok').then((overview) {
        expect(overview.summary.total, 1);
        // Even the fallback classifies through StockStateView, so a withdrawn
        // listing is still not "in stock" despite its 11 remaining units.
        expect(overview.summary.inStock, 0);
        expect(overview.summary.lowStock, 0);
        expect(overview.summary.outOfStock, 0);
        expect(overview.summary.totalUnits, 11);
      });
    });

    test('requests the list view (the only one carrying freshness)', () {
      final client = FakeApiClient(response: body(withSummary: true));
      final repo = ApiInventoryRepository(client);
      return repo.fetchInventoryOverview(10, 'tok').then((_) {
        expect(client.lastGetPath, ApiEndpoints.inventory('10'));
        expect(client.lastGetQuery, {'view': 'list'});
      });
    });
  });

  group('updateLowStockThreshold', () {
    test('PATCHes the threshold and returns the server-derived state', () {
      final client = FakeApiClient(response: {
        'shop_product_id': 77,
        'previous_low_stock_threshold': 5,
        'low_stock_threshold': 10,
        'quantity': 8,
        'stock_status': 'LOW_STOCK',
        'last_inventory_update': '2026-09-18T10:00:00Z',
      });
      final repo = ApiInventoryRepository(client);
      return repo.updateLowStockThreshold(10, 77, 10, 'tok').then((result) {
        expect(client.lastPatchPath,
            ApiEndpoints.lowStockThreshold('10', '77'));
        expect(client.lastPatchBody, {'low_stock_threshold': 10});
        expect(result.lowStockThreshold, 10);
        expect(result.previousLowStockThreshold, 5);
        expect(result.quantity, 8);
        // The state came from the server, not from a client-side derivation.
        expect(result.stockState.label, 'Low stock');
        expect(result.stockState.isLowStock, isTrue);
      });
    });
  });

  group('fetchStockAdjustments', () {
    test('GETs the adjustment trail and parses each row', () {
      final client = FakeApiClient(response: {
        'shop_product_id': 77,
        'count': 2,
        'adjustments': [
          {
            'id': 900,
            'adjustment_type': 'RESTOCK',
            'quantity_adjustment': 10,
            'reason': 'Delivery received',
            'approved_by': 3,
            'approved_at': '2026-09-18T09:00:00Z',
          },
          {
            'id': 901,
            'adjustment_type': 'DAMAGE',
            'quantity_adjustment': -2,
            'reason': 'Broken in transit',
            'created_at': '2026-09-18T08:00:00Z',
          },
        ],
      });
      final repo = ApiInventoryRepository(client);
      return repo.fetchStockAdjustments(10, 77, 'tok').then((history) {
        expect(client.lastGetPath,
            ApiEndpoints.stockAdjustmentHistory('10', '77'));
        expect(history.shopProductId, 77);
        expect(history.adjustments.length, 2);
        expect(history.adjustments.first.quantityAdjustment, 10);
        expect(history.adjustments.last.quantityAdjustment, -2);
        // approval time when present, else creation time
        expect(history.adjustments.first.occurredAt, isNotNull);
        expect(history.adjustments.last.occurredAt, isNotNull);
      });
    });

    test('an empty trail parses without crashing', () {
      final repo = ApiInventoryRepository(FakeApiClient(response: {
        'shop_product_id': 77,
        'adjustments': [],
        'count': 0,
      }));
      return repo.fetchStockAdjustments(10, 77, 'tok').then((history) {
        expect(history.isEmpty, isTrue);
        expect(history.adjustments, isEmpty);
      });
    });
  });

  group('FakeProductRepo mirrors the server rule', () {
    test('threshold decides LOW_STOCK, not the quantity alone', () {
      final repo = FakeProductRepo(items: [
        ShopProductItem.fromJson({
          'id': 42,
          'name': 'Atta 5kg',
          'status': 'ACTIVE',
          'stock_status': 'IN_STOCK',
          'quantity': 8,
          'price': 120,
        }),
      ]);
      return repo.updateLowStockThreshold(10, 42, 10, 'tok').then((result) {
        expect(result.lowStockThreshold, 10);
        // 8 units at threshold 10 is LOW_STOCK — the quantity did not move.
        expect(result.stockStatus, 'LOW_STOCK');
        expect(repo.thresholdCalls, 1);
        expect(repo.lastThresholdId, 42);
        expect(repo.lastThresholdValue, 10);
      });
    });
  });
}

/// Records the request and replays a canned response payload.
class FakeApiClient implements ApiClient {
  FakeApiClient({required this.response});

  final Map<String, dynamic> response;
  String? lastGetPath;
  Map<String, dynamic>? lastGetQuery;
  String? lastPatchPath;
  Object? lastPatchBody;

  @override
  Dio get dio => throw UnimplementedError('not used by repositories in tests');

  @override
  void Function(ApiException error)? get onUnauthorized => null;

  @override
  Future<dynamic> get(String path,
      {Map<String, dynamic>? query, String? token}) async {
    lastGetPath = path;
    lastGetQuery = query;
    return response;
  }

  @override
  Future<dynamic> post(String path, {Object? body, String? token}) async {
    lastPatchPath = path;
    lastPatchBody = body;
    return response;
  }

  @override
  Future<dynamic> patch(String path, {Object? body, String? token}) async {
    lastPatchPath = path;
    lastPatchBody = body;
    return response;
  }

  @override
  Future<dynamic> put(String path, {Object? body, String? token}) async =>
      response;

  @override
  Future<dynamic> delete(String path, {String? token}) async => response;

  @override
  Future<dynamic> postMultipart(
    String path, {
    required FormData form,
    String? token,
  }) async =>
      response;

  @override
  Future<void> postFormToExternal(String url, {required FormData form}) async {}
}

