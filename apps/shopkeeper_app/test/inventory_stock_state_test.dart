import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/presentation/widgets/inventory_shared.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_models.dart';

/// Inventory stock states (IN_STOCK / LOW_STOCK / OUT_OF_STOCK / UNKNOWN /
/// DISCONTINUED).
///
/// `DISCONTINUED` is carried on `ShopProduct.status`, NOT on
/// `Inventory.stock_status` — the backend's stock enum has no such member
/// (IN_STOCK / LOW_STOCK / LIMITED_STOCK / OUT_OF_STOCK / UNKNOWN /
/// PRE_ORDER / BACK_ORDER). These tests pin the merge so a discontinued
/// listing can never render as "In stock", and pin that every state is read
/// from the server vocabulary instead of a duplicated client enum.
void main() {
  ShopProductItem item({
    String status = 'ACTIVE',
    String stockStatus = 'IN_STOCK',
    int quantity = 10,
  }) =>
      ShopProductItem.fromJson({
        'id': 1,
        'name': 'Test item',
        'status': status,
        'stock_status': stockStatus,
        'quantity': quantity,
        'price': 100,
      });

  group('every required state resolves from server values', () {
    test('IN_STOCK', () {
      final i = item(stockStatus: 'IN_STOCK');
      expect(i.stockState.label, 'In stock');
      expect(i.stockState.isInStock, isTrue);
    });

    test('LOW_STOCK', () {
      final i = item(stockStatus: 'LOW_STOCK', quantity: 2);
      expect(i.stockState.label, 'Low stock');
      expect(i.stockState.isLowStock, isTrue);
    });

    test('OUT_OF_STOCK', () {
      final i = item(stockStatus: 'OUT_OF_STOCK', quantity: 0);
      expect(i.stockState.label, 'Out of stock');
      expect(i.stockState.isOutOfStock, isTrue);
    });

    test('UNKNOWN', () {
      final i = item(stockStatus: 'UNKNOWN');
      expect(i.stockState.label, 'Unknown');
      expect(i.stockState.isUnknown, isTrue);
    });

    test('DISCONTINUED', () {
      final i = item(status: 'DISCONTINUED');
      expect(i.stockState.label, 'Discontinued');
      expect(i.stockState.isDiscontinued, isTrue);
    });
  });

  group('DISCONTINUED is a product status, not a stock status', () {
    test('stock_status alone can never produce Discontinued', () {
      // Guards the regression: the backend stock enum has no DISCONTINUED
      // member, so resolving the chip from stock_status alone made the
      // "Discontinued" state unreachable in the app.
      final i = item(stockStatus: 'IN_STOCK');
      expect(i.isDiscontinued, isFalse);
      expect(i.stockState.isDiscontinued, isFalse);
    });

    test('a discontinued listing outranks its remaining stock', () {
      final i = item(
        status: 'DISCONTINUED',
        stockStatus: 'IN_STOCK',
        quantity: 40,
      );
      expect(i.isDiscontinued, isTrue);
      expect(i.stockState.label, 'Discontinued');
      // The old behaviour rendered this as "In stock" despite the listing
      // being withdrawn from sale.
      expect(i.stockState.isInStock, isFalse);
    });

    test('a discontinued listing is never low-stock or out-of-stock', () {
      final low = item(
        status: 'DISCONTINUED',
        stockStatus: 'LOW_STOCK',
        quantity: 2,
      );
      expect(low.stockState.isLowStock, isFalse);
      expect(low.stockState.label, 'Discontinued');

      final out = item(
        status: 'DISCONTINUED',
        stockStatus: 'OUT_OF_STOCK',
        quantity: 0,
      );
      expect(out.stockState.isOutOfStock, isFalse);
      expect(out.stockState.label, 'Discontinued');
    });

    test('other product statuses do not disturb the stock state', () {
      expect(item(status: 'ACTIVE').stockState.label, 'In stock');
      expect(item(status: 'INACTIVE').stockState.label, 'In stock');
    });
  });

  group('one shared mapping (no duplicated client enum)', () {
    test('canonical value is the real server value', () {
      expect(StockStateView.discontinued.value, 'DISCONTINUED');
      expect(StockStateView.outOfStock.value, 'OUT_OF_STOCK');
      expect(StockStateView.unknown.value, 'UNKNOWN');
    });

    test('legacy misspelling resolves as an alias', () {
      expect(StockStateView.of('DISCONTINUOUS').label, 'Discontinued');
      expect(StockStateView.of('DISCONTINUOUS').isDiscontinued, isTrue);
    });

    test('server aliases collapse onto one canonical state', () {
      expect(StockStateView.of('LIMITED_STOCK').value, 'LOW_STOCK');
      expect(StockStateView.of('BACK_ORDER').isLowStock, isTrue);
      expect(StockStateView.of('PRE_ORDER').isInStock, isTrue);
    });

    test('an unseen server value humanises instead of throwing', () {
      expect(StockStateView.of('MADE_TO_ORDER').label, 'Made To Order');
      expect(StockStateView.of('MADE_TO_ORDER').isDiscontinued, isFalse);
    });

    test('null / blank stock status falls back to Unknown', () {
      expect(StockStateView.of(null).label, 'Unknown');
      expect(StockStateView.of('').label, 'Unknown');
    });

    test('a payload missing stock_status parses as UNKNOWN', () {
      final i = ShopProductItem.fromJson({
        'id': 1,
        'name': 'x',
        'status': 'ACTIVE',
        'price': 1,
      });
      expect(i.stockStatus, 'UNKNOWN');
      expect(i.stockState.label, 'Unknown');
    });
  });

  group('chip colour reflects the merged state', () {
    test('discontinued is muted, never the in-stock green', () {
      final discontinued = item(status: 'DISCONTINUED', stockStatus: 'IN_STOCK');
      expect(
        stockStateColor(discontinued.stockState),
        stockStateColor(StockStateView.unknown),
      );
      expect(
        stockStateColor(discontinued.stockState),
        isNot(stockStateColor(item().stockState)),
      );
    });
  });
}