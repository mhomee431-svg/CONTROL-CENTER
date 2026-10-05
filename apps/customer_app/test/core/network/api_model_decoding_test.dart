import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/features/customer/domain/models/customer_models.dart';
import 'package:hyperlocal_app/features/order/domain/models/order_models.dart';

/// Model-level decoding against responses the app has never seen.
///
/// These sit above the `JsonMap` unit tests on purpose: the reader being total
/// is necessary but not sufficient. What matters here is that a real MODEL
/// built from a changed response is still usable, and — more importantly — that
/// it never asserts something the backend did not say.
void main() {
  group('OrderStatus decoding', () {
    test('recognises every documented wire value', () {
      for (final status in OrderStatus.values) {
        expect(OrderStatus.fromValue(status.value), status);
      }
    });

    test('a multi-word status decodes despite the camelCase Dart name', () {
      // `values.byName('READY_FOR_PICKUP')` throws: the Dart member is
      // `readyForPickup`. This is the whole reason the codec exists.
      expect(
        OrderStatus.fromValue('READY_FOR_PICKUP'),
        OrderStatus.readyForPickup,
      );
      expect(
        OrderStatus.fromValue('OUT_FOR_DELIVERY'),
        OrderStatus.outForDelivery,
      );
    });

    test('an UNKNOWN status falls back instead of throwing', () {
      // A new backend status must not be able to empty the customer's order
      // list. It becomes the initial state, and `isRecognised` lets the UI
      // know it did not really learn that.
      expect(() => OrderStatus.fromValue('ON_HOLD'), returnsNormally);
      expect(OrderStatus.fromValue('ON_HOLD'), OrderStatus.pending);
      expect(isRecognised('ON_HOLD'), isFalse);
      expect(isRecognised('PENDING'), isTrue);
    });

    test('null and blank fall back', () {
      expect(OrderStatus.fromValue(null), OrderStatus.pending);
      expect(OrderStatus.fromValue('  '), OrderStatus.pending);
    });

    test('PaymentStatus behaves the same way', () {
      expect(
        PaymentStatus.fromValue('PARTIALLY_REFUNDED'),
        PaymentStatus.partiallyRefunded,
      );
      expect(PaymentStatus.fromValue('DISPUTED'), PaymentStatus.pending);
    });
  });

  group('Order decoding tolerates a changed response', () {
    test('an entirely empty object yields a usable order', () {
      // The old `json['id'] as int` would have thrown here and taken the
      // whole list down over one missing field.
      final order = Order.fromJson(const {});
      expect(order.id, 0);
      expect(order.status, OrderStatus.pending);
      expect(order.items, isEmpty);
    });

    test('a null or wrongly-typed payload does not throw', () {
      expect(() => Order.fromJson(null), returnsNormally);
      expect(() => Order.fromJson('not an object'), returnsNormally);
      expect(() => Order.fromJson(42), returnsNormally);
    });

    test('numeric strings are accepted for id and totals', () {
      // A backend that starts sending ids as strings is a version change the
      // app should ride out.
      final order = Order.fromJson(const {
        'id': '9001',
        'shop_id': '12',
        'total_amount': '249.50',
        'status': 'CONFIRMED',
      });
      expect(order.id, 9001);
      expect(order.shopId, 12);
      expect(order.totalAmount, 249.5);
      expect(order.status, OrderStatus.confirmed);
    });

    test('a malformed line item is dropped, the rest survive', () {
      final order = Order.fromJson(const {
        'id': 1,
        'items': [
          {'id': 10, 'product_name': 'Good item', 'quantity': 1},
          'garbage',
          null,
          {'id': 11, 'product_name': 'Also good'},
        ],
      });
      expect(order.items.length, 2);
      expect(order.items.first.productName, 'Good item');
      expect(order.items.first.quantity, 1);
    });

    test('a missing created_at keeps the documented epoch sentinel', () {
      final order = Order.fromJson(const {'id': 1});
      expect(order.createdAt.millisecondsSinceEpoch, 0);
      // updatedAt falls back to createdAt rather than independently becoming
      // 1970, which would imply the order predates its own creation.
      expect(order.updatedAt, order.createdAt);
    });
  });

  group('OrderListResponse decoding', () {
    test('accepts `orders` and the `results` alias', () {
      final a = OrderListResponse.fromJson(const {
        'orders': [
          {'id': 1},
        ],
        'total': 1,
      });
      final b = OrderListResponse.fromJson(const {
        'results': [
          {'id': 1},
        ],
        'total': 1,
      });
      expect(a.orders.length, 1);
      expect(b.orders.length, 1);
    });

    test('a missing has_next is derived, not assumed false', () {
      // Defaulting to `false` would hide further pages behind a missing
      // "Load more" button.
      final full = OrderListResponse.fromJson(const {
        'orders': [
          {'id': 1},
          {'id': 2},
        ],
        'total': 10,
        'page_size': 2,
      });
      expect(full.hasNext, isTrue);
    });
  });

  group('Customer model decoding', () {
    test('a favourite with a missing id decodes instead of throwing', () {
      // `json['id'] as int` used to throw here.
      final favourite = CustomerFavorite.fromJson(const {
        'item_type': 'product',
        'item_id': 55,
      });
      expect(favourite.id, 0);
      expect(favourite.itemType, 'product');
      expect(favourite.itemId, 55);
    });

    test('a favourite with a non-object item decodes to null', () {
      final favourite = CustomerFavorite.fromJson(const {
        'id': 1,
        'item': 'deleted',
      });
      expect(favourite.item, isNull);
    });

    test('a favourite whose nested item is malformed does not throw', () {
      expect(
        () => CustomerFavorite.fromJson(const {
          'id': 1,
          'item': {'name': 42},
        }),
        returnsNormally,
      );
    });

    test('an unknown item_type is kept verbatim, not rejected', () {
      // `item_type` is an open vocabulary the backend keeps extending;
      // mapping it to a closed enum would need a release per new type.
      final favourite = CustomerFavorite.fromJson(const {
        'id': 1,
        'item_type': 'SOME_FUTURE_KIND',
      });
      expect(favourite.itemType, 'SOME_FUTURE_KIND');
    });

    test('a share payload without a price range keeps null', () {
      // Null means "no live offers"; 0-to-0 would read as "free".
      final payload = ProductSharePayload.fromJson(const {
        'product_master_id': 7,
        'name': 'Shampoo',
      });
      expect(payload.priceRange, isNull);
      expect(payload.shopCount, isNull);
    });

    test('a price range sent as formatted strings still decodes', () {
      final payload = ProductSharePayload.fromJson(const {
        'price_range': {'min': '40.50', 'max': '1,299.00'},
      });
      expect(payload.priceRange?.min, 40.5);
      expect(payload.priceRange?.max, 1299.0);
    });
  });
}
