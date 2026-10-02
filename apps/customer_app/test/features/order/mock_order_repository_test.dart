import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/features/order/data/mock_order_repository.dart';
import 'package:hyperlocal_app/features/order/domain/models/order_models.dart';

/// The in-memory order repository used when no backend is configured.
///
/// The important property under test is that it behaves like the REAL backend,
/// not like whatever is convenient. A mock that let a customer cancel a
/// delivered order, or skip from PENDING to DELIVERED, would let them rehearse a
/// flow the server then rejects — and they would find out at the worst possible
/// moment.
void main() {
  late MockOrderRepository repo;

  setUp(() {
    repo = MockOrderRepository(now: () => DateTime(2026, 9, 27, 12, 0));
  });

  /// Finds a seeded order by its status, so tests do not depend on ids.
  Future<Order> seededWith(OrderStatus status) async {
    final all = await repo.listOrders();
    return all.orders.firstWhere((o) => o.status == status);
  }

  group('MockOrderRepository seeding', () {
    test('ships a non-empty, clearly-labelled order history', () async {
      final result = await repo.listOrders();

      // No backend configured used to mean an exception, so the screen was
      // unreachable. It now has real content to render.
      expect(result.orders, isNotEmpty);
      expect(result.total, result.orders.length);

      // Obfuscated-looking order numbers are reserved for real money.
      for (final order in result.orders) {
        expect(order.orderNumber, startsWith('ORD-DEMO-'));
      }
    });

    test('lists newest first', () async {
      final result = await repo.listOrders();
      final stamps = result.orders.map((o) => o.createdAt).toList();

      for (var i = 1; i < stamps.length; i++) {
        expect(stamps[i].isAfter(stamps[i - 1]), isFalse);
      }
    });
  });

  group('MockOrderRepository createOrder', () {
    test('computes totals the same way the backend does', () async {
      final order = await repo.createOrder(
        const OrderCreate(
          shopId: 7,
          deliveryFee: 25,
          taxAmount: 18,
          discountAmount: 10,
          items: [
            OrderItemCreate(
              productMasterId: 1,
              productName: 'Shampoo',
              quantity: 3,
              price: 49.5,
            ),
          ],
        ),
      );

      // subtotal = 148.50; total = 148.50 + 25 + 18 - 10 = 181.50
      expect(order.subtotalAmount, 148.5);
      expect(order.totalAmount, 181.5);
      expect(order.totalItems, 3);
      expect(order.status, OrderStatus.pending);
    });

    test(
      'a discount larger than the basket never yields a negative total',
      () async {
        final order = await repo.createOrder(
          const OrderCreate(
            shopId: 7,
            discountAmount: 500,
            items: [
              OrderItemCreate(
                productMasterId: 1,
                productName: 'Cheap thing',
                quantity: 1,
                price: 10,
              ),
            ],
          ),
        );

        // The backend raises on a negative computed total, so the mock clamps.
        expect(order.totalAmount, 0);
      },
    );

    test('an empty basket is rejected, matching the backend', () async {
      // "Succeeding" here would create a nonsense order in the customer's
      // history that the real service would never have accepted.
      expect(
        () => repo.createOrder(const OrderCreate(shopId: 1, items: [])),
        throwsA(isA<OrderMutationException>()),
      );
    });
  });

  group('MockOrderRepository status transitions', () {
    test('a legal transition is applied', () async {
      final pending = await repo.createOrder(_basket());
      expect(pending.status, OrderStatus.pending);

      final confirmed = await repo.updateOrderStatus(
        '${pending.id}',
        const OrderStatusUpdate(status: 'CONFIRMED'),
      );
      expect(confirmed.status, OrderStatus.confirmed);
      // The milestone is stamped so the timeline has real data.
      expect(confirmed.confirmedAt, isNotNull);
    });

    test('an illegal transition is refused', () async {
      final pending = await repo.createOrder(_basket());

      // PENDING cannot jump straight to DELIVERED.
      expect(
        () => repo.updateOrderStatus(
          '${pending.id}',
          const OrderStatusUpdate(status: 'DELIVERED'),
        ),
        throwsA(isA<OrderMutationException>()),
      );
    });

    test('a terminal order accepts no further transitions', () async {
      final cancelled = await seededWith(OrderStatus.cancelled);

      for (final next in ['CONFIRMED', 'PREPARING', 'DELIVERED']) {
        expect(
          () => repo.updateOrderStatus(
            '${cancelled.id}',
            OrderStatusUpdate(status: next),
          ),
          throwsA(isA<OrderMutationException>()),
          reason: 'CANCELLED must not accept a move to $next',
        );
      }
    });

    test('the transition table matches the backend contract exactly', () {
      // If the backend ever changes its table, this fails loudly rather than
      // letting the two implementations drift apart silently.
      //
      // `const <String>{}` is required on the terminal states: a bare `{}` in a
      // map literal infers an empty MAP, not an empty Set, and the comparison
      // would then fail for a reason that has nothing to do with behaviour.
      expect(MockOrderRepository.validStatusTransitions, {
        'PENDING': {'CONFIRMED', 'CANCELLED', 'FAILED'},
        'CONFIRMED': {'PREPARING', 'CANCELLED'},
        'PREPARING': {'READY_FOR_PICKUP', 'CANCELLED'},
        'READY_FOR_PICKUP': {'OUT_FOR_DELIVERY', 'CANCELLED'},
        'OUT_FOR_DELIVERY': {'DELIVERED'},
        'DELIVERED': {'REFUNDED'},
        'CANCELLED': const <String>{},
        'REFUNDED': const <String>{},
        'FAILED': const <String>{},
      });
    });

    test('terminal statuses really have no outgoing transitions', () {
      for (final terminal in [
        OrderStatus.cancelled,
        OrderStatus.refunded,
        OrderStatus.failed,
      ]) {
        expect(
          MockOrderRepository.validStatusTransitions[terminal.value],
          isEmpty,
          reason: '$terminal must be terminal',
        );
      }
    });
  });

  group('MockOrderRepository cancellation', () {
    test('a cancellable order is cancelled', () async {
      final preparing = await seededWith(OrderStatus.preparing);

      final cancelled = await repo.cancelOrder('${preparing.id}');
      expect(cancelled.status, OrderStatus.cancelled);
      expect(cancelled.cancelReason, isNotNull);
      expect(cancelled.cancelledAt, isNotNull);
    });

    test('a dispatched order cannot be cancelled', () async {
      final moving = await seededWith(OrderStatus.outForDelivery);

      // Physically with a rider — the customer can no longer call it off.
      expect(
        () => repo.cancelOrder('${moving.id}'),
        throwsA(isA<OrderMutationException>()),
      );
    });

    test('a delivered order cannot be cancelled', () async {
      final done = await seededWith(OrderStatus.delivered);
      expect(
        () => repo.cancelOrder('${done.id}'),
        throwsA(isA<OrderMutationException>()),
      );
    });

    test('cancelling twice is refused rather than silently accepted', () async {
      final preparing = await seededWith(OrderStatus.preparing);
      await repo.cancelOrder('${preparing.id}');

      expect(
        () => repo.cancelOrder('${preparing.id}'),
        throwsA(isA<OrderMutationException>()),
      );
    });
  });

  group('MockOrderRepository lookups', () {
    test('an unknown id is a not-found, not a generic failure', () async {
      // The two failures need different UI copy, so they must not be the
      // same exception.
      expect(
        () => repo.getOrderById('999999'),
        throwsA(isA<OrderNotFoundException>()),
      );
      expect(
        () => repo.trackOrder('999999'),
        throwsA(isA<OrderNotFoundException>()),
      );
    });

    test('a non-numeric id is a not-found rather than a crash', () async {
      expect(
        () => repo.getOrderById('abc'),
        throwsA(isA<OrderNotFoundException>()),
      );
    });

    test('a known id round-trips through get and track', () async {
      final order = await seededWith(OrderStatus.confirmed);

      expect((await repo.getOrderById('${order.id}')).id, order.id);
      expect((await repo.trackOrder('${order.id}')).id, order.id);
    });
  });

  group('MockOrderRepository pagination', () {
    test('limit and offset page through the history', () async {
      final all = await repo.listOrders();
      expect(all.orders.length, greaterThan(2));

      final firstPage = await repo.listOrders(limit: 2);
      expect(firstPage.orders.length, 2);
      expect(firstPage.hasNext, isTrue);
      expect(firstPage.total, all.total);

      final secondPage = await repo.listOrders(limit: 2, offset: 2);
      // No overlap between pages.
      final firstIds = firstPage.orders.map((o) => o.id).toSet();
      expect(secondPage.orders.every((o) => !firstIds.contains(o.id)), isTrue);
    });

    test('an offset past the end yields an empty page, not an error', () async {
      final page = await repo.listOrders(limit: 10, offset: 999);
      expect(page.orders, isEmpty);
      expect(page.hasNext, isFalse);
    });
  });
}

OrderCreate _basket() => const OrderCreate(
  shopId: 1,
  items: [
    OrderItemCreate(
      productMasterId: 1,
      productName: 'Test item',
      quantity: 2,
      price: 50,
    ),
  ],
);
