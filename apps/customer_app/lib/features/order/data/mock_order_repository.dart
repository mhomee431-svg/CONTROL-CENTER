import 'dart:math';

import '../domain/models/order_models.dart';
import '../domain/order_repository.dart';

/// In-memory [OrderRepository] used when no backend is configured.
///
/// WHY THIS EXISTS
/// ---------------
/// `orderRepositoryProvider` used to `throw UnsupportedError` in a build with
/// no `API_BASE_URL`. That is worse than useless: a Riverpod provider that
/// throws on read takes down the whole route subtree, so the customer could not
/// even reach the orders screen to be told orders need a backend. Following the
/// same convention as notifications and profile, this feature now degrades to
/// local demo data instead.
///
/// The seed data is deliberately boring and obviously synthetic (order numbers
/// like `ORD-DEMO-1000`, a "Demo Basket Item") so nobody can mistake a mock
/// order for a real purchase.
///
/// The state machine here MIRRORS `app/services/order_service.py` — the same
/// transition table, the same terminal states, the same "cannot cancel once
/// dispatched" rule. A mock that allowed different transitions would let a
/// customer rehearse a flow the real backend then rejects, which is the worst
/// possible moment to discover the difference.
/// 
class MockOrderRepository implements OrderRepository {
  /// Allowed forward transitions: current status -> {allowed next statuses}.
  /// Copied verbatim from the backend's `_VALID_STATUS_TRANSITIONS`.
  static const Map<String, Set<String>> validStatusTransitions = {
    'PENDING': {'CONFIRMED', 'CANCELLED', 'FAILED'},
    'CONFIRMED': {'PREPARING', 'CANCELLED'},
    'PREPARING': {'READY_FOR_PICKUP', 'CANCELLED'},
    'READY_FOR_PICKUP': {'OUT_FOR_DELIVERY', 'CANCELLED'},
    'OUT_FOR_DELIVERY': {'DELIVERED'},
    'DELIVERED': {'REFUNDED'},
    'CANCELLED': {},
    'REFUNDED': {},
    'FAILED': {},
  };

  /// Statuses a customer is still allowed to cancel.
  ///
  /// Mirrors the backend's `is_cancellable` column. Once an order is out for
  /// delivery it is physically with a rider, so cancelling is no longer the
  /// customer's decision to make.
  static const Set<String> cancellableStatuses = {
    'PENDING',
    'CONFIRMED',
    'PREPARING',
    'READY_FOR_PICKUP',
  };

  /// Deterministic seed keeps the mock reproducible across runs.
  MockOrderRepository({DateTime Function()? now, int seed = 0})
    : _now = now ?? DateTime.now,
      _random = Random(seed) {
    _seedOrders();
  }

  final DateTime Function() _now;
  final Random _random;
  final Map<int, Order> _orders = {};
  int _nextId = 1000;
  int _nextItemId = 1;

  @override
  Future<Order> createOrder(OrderCreate order) async {
    // A checkout for an empty basket is a client bug, not a valid order. The
    // backend rejects it, so the mock must too rather than "succeeding" and
    // creating a nonsense order the customer then sees in their history.
    if (order.items.isEmpty) {
      throw const OrderMutationException('An order needs at least one item');
    }

    final now = _now();
    final id = _nextId++;
    final items = order.items
        .map(
          (item) => OrderItem(
            id: _nextItemId++,
            orderId: id,
            productMasterId: item.productMasterId,
            productName: item.productName,
            variantId: item.variantId,
            variantName: item.variantName,
            shopProductId: item.shopProductId,
            quantity: item.quantity,
            price: item.price,
            totalPrice: item.price * item.quantity,
            imageUrl: item.imageUrl,
          ),
        )
        .toList(growable: false);

    // Snapshot the backend's arithmetic so the totals shown here match what the
    // real service computes for the same basket.
    final subtotal = _round(
      items.fold<double>(0, (sum, i) => sum + i.totalPrice),
    );
    final total = _round(
      subtotal + order.deliveryFee + order.taxAmount - order.discountAmount,
    );

    final created = Order(
      id: id,
      orderNumber: 'ORD-DEMO-$id',
      userId: 0,
      shopId: order.shopId,
      status: OrderStatus.pending,
      subtotalAmount: subtotal,
      deliveryFee: order.deliveryFee,
      discountAmount: order.discountAmount,
      taxAmount: order.taxAmount,
      totalAmount: total < 0 ? 0 : total,
      totalItems: items.fold<int>(0, (sum, i) => sum + i.quantity),
      notes: order.notes,
      shippingAddressJson: order.shippingAddressJson,
      placedAt: now,
      createdAt: now,
      updatedAt: now,
      items: items,
    );

    _orders[id] = created;
    return created;
  }


  @override
  Future<Order> getOrderById(String orderId) async => _require(orderId);

  @override
  Future<OrderListResponse> listOrders({int? limit, int? offset}) async {
    // Newest first, matching the backend's ordering so pagination behaves the
    // same way in the mock as in production.
    final all = _orders.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Bound into locals first: promotion of a nullable parameter does not
    // survive into `clamp`, and each of these is already non-null by the `??`.
    final from = offset ?? 0;
    final size = limit ?? all.length;

    final start = from.clamp(0, all.length);
    final end = (start + size).clamp(start, all.length);
    final page = all.sublist(start, end);

    return OrderListResponse(
      orders: page,
      total: all.length,
      // 1-based page number for the caller's offset, matching the backend's
      // page/page_size contract.
      page: (from ~/ 50) + 1,
      pageSize: size,
      hasNext: end < all.length,
    );
  }

  @override
  Future<Order> updateOrderStatus(
    String orderId,
    OrderStatusUpdate update,
  ) async {
    final existing = _require(orderId);
    final next = OrderStatus.fromValue(update.status);
    final allowed = validStatusTransitions[existing.status.value] ?? const {};

    if (!allowed.contains(next.value)) {
      // Same 409 the backend returns for an illegal transition. Refusing is the
      // point: silently accepting it would let the UI show a state the server
      // would never reach.
      throw OrderMutationException(
        'Cannot transition order from '
        '${existing.status.value} to ${next.value}',
      );
    }

    final now = _now();
    final updated = _replace(
      existing,
      status: next,
      updatedAt: now,
      // Stamp the milestone the new status represents, exactly as the backend
      // does, so the timeline on the detail screen has real data.
      confirmedAt: next == OrderStatus.confirmed ? now : existing.confirmedAt,
      preparingAt: next == OrderStatus.preparing ? now : existing.preparingAt,
      readyAt: next == OrderStatus.readyForPickup ? now : existing.readyAt,
      outForDeliveryAt:
          next == OrderStatus.outForDelivery ? now : existing.outForDeliveryAt,
      deliveredAt: next == OrderStatus.delivered ? now : existing.deliveredAt,
      cancelledAt: next == OrderStatus.cancelled ? now : existing.cancelledAt,
    );
    _orders[updated.id] = updated;
    return updated;
  }

  @override
  Future<Order> cancelOrder(String orderId) async {
    final existing = _require(orderId);

    if (!cancellableStatuses.contains(existing.status.value)) {
      throw const OrderMutationException('Order can no longer be cancelled');
    }

    final now = _now();
    final updated = _replace(
      existing,
      status: OrderStatus.cancelled,
      cancelReason: 'Cancelled by customer',
      cancelledAt: now,
      updatedAt: now,
    );
    _orders[updated.id] = updated;
    return updated;
  }

  @override
  Future<Order> trackOrder(String orderId) async => _require(orderId);

  // ── internals ──────────────────────────────────────────────────────────
  Order _require(String orderId) {
    final id = int.tryParse(orderId);
    if (id == null) {
      throw OrderNotFoundException(orderId);
    }
    final found = _orders[id];
    if (found == null) {
      throw OrderNotFoundException(orderId);
    }
    return found;
  }

  /// Rebuilds an [Order] with the given overrides, since the model is
  /// immutable and has no generated `copyWith`.
  static Order _replace(
    Order o, {
    OrderStatus? status,
    String? cancelReason,
    DateTime? confirmedAt,
    DateTime? preparingAt,
    DateTime? readyAt,
    DateTime? outForDeliveryAt,
    DateTime? deliveredAt,
    DateTime? cancelledAt,
    DateTime? updatedAt,
  }) => Order(
    id: o.id,
    orderNumber: o.orderNumber,
    userId: o.userId,
    customerId: o.customerId,
    shopId: o.shopId,
    status: status ?? o.status,
    paymentMethod: o.paymentMethod,
    paymentStatus: o.paymentStatus,
    currency: o.currency,
    subtotalAmount: o.subtotalAmount,
    deliveryFee: o.deliveryFee,
    discountAmount: o.discountAmount,
    taxAmount: o.taxAmount,
    totalAmount: o.totalAmount,
    totalItems: o.totalItems,
    notes: o.notes,
    shippingAddressJson: o.shippingAddressJson,
    placedAt: o.placedAt,
    confirmedAt: confirmedAt ?? o.confirmedAt,
    preparingAt: preparingAt ?? o.preparingAt,
    readyAt: readyAt ?? o.readyAt,
    outForDeliveryAt: outForDeliveryAt ?? o.outForDeliveryAt,
    deliveredAt: deliveredAt ?? o.deliveredAt,
    cancelledAt: cancelledAt ?? o.cancelledAt,
    cancelReason: cancelReason ?? o.cancelReason,
    createdAt: o.createdAt,
    updatedAt: updatedAt ?? o.updatedAt,
    items: o.items,
  );

  void _seedOrders() {
    // A spread of statuses so every branch of the order UI has something to
    // render, and so the "can I still cancel this?" rule is visible in a demo.
    final seeds = <(OrderStatus, double, int)>[
      (OrderStatus.delivered, 349, 2),
      (OrderStatus.outForDelivery, 189, 1),
      (OrderStatus.preparing, 249, 3),
      (OrderStatus.confirmed, 129, 1),
      (OrderStatus.cancelled, 89, 1),
    ];

    var minutesAgo = 0;
    for (final (status, unitPrice, quantity) in seeds) {
      final now = _now().subtract(Duration(minutes: minutesAgo += 90));
      final id = _nextId++;
      final itemId = _nextItemId++;
      final total = _round(unitPrice * quantity);

      _orders[id] = Order(
        id: id,
        orderNumber: 'ORD-DEMO-$id',
        userId: 0,
        shopId: 1,
        status: status,
        subtotalAmount: total,
        deliveryFee: status == OrderStatus.cancelled ? 0 : 25,
        totalAmount: status == OrderStatus.cancelled ? total : _round(total + 25),
        totalItems: quantity,
        placedAt: now,
        createdAt: now,
        updatedAt: now,
        confirmedAt: now,
        outForDeliveryAt: status == OrderStatus.outForDelivery ? now : null,
        deliveredAt: status == OrderStatus.delivered ? now : null,
        cancelledAt: status == OrderStatus.cancelled ? now : null,
        cancelReason: status == OrderStatus.cancelled
            ? 'Cancelled by customer'
            : null,
        items: [
          OrderItem(
            id: itemId,
            orderId: id,
            productMasterId: 1,
            productName: 'Demo Basket Item',
            quantity: quantity,
            price: unitPrice,
            totalPrice: total,
            itemStatus: status.value,
          ),
        ],
      );
    }
  }

  static double _round(double value) => (value * 100).roundToDouble() / 100;
}

