// Customer-facing order models with explicit JSON serialization.
//
// These models intentionally do not depend on generated files so the order
// feature remains buildable in environments that have Dart but not Flutter.

enum OrderStatus {
  pending('PENDING'),
  confirmed('CONFIRMED'),
  preparing('PREPARING'),
  readyForPickup('READY_FOR_PICKUP'),
  outForDelivery('OUT_FOR_DELIVERY'),
  delivered('DELIVERED'),
  cancelled('CANCELLED'),
  refunded('REFUNDED'),
  failed('FAILED');

  final String value;
  const OrderStatus(this.value);

  static OrderStatus fromValue(String? value) => values.firstWhere(
    (status) => status.value == value,
    orElse: () => OrderStatus.pending,
  );
}

enum PaymentStatus {
  pending('PENDING'),
  paid('PAID'),
  failed('FAILED'),
  refunded('REFUNDED'),
  partiallyRefunded('PARTIALLY_REFUNDED');

  final String value;
  const PaymentStatus(this.value);

  static PaymentStatus fromValue(String? value) => values.firstWhere(
    (status) => status.value == value,
    orElse: () => PaymentStatus.pending,
  );
}

class OrderItem {
  final int id;
  final int orderId;
  final int productMasterId;
  final String productName;
  final int? variantId;
  final String? variantName;
  final int? shopProductId;
  final int quantity;
  final double price;
  final double totalPrice;
  final String? imageUrl;
  final String itemStatus;

  const OrderItem({
    required this.id,
    required this.orderId,
    required this.productMasterId,
    required this.productName,
    this.variantId,
    this.variantName,
    this.shopProductId,
    required this.quantity,
    required this.price,
    required this.totalPrice,
    this.imageUrl,
    this.itemStatus = 'PENDING',
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
    id: _asInt(json['id']),
    orderId: _asInt(json['order_id']),
    productMasterId: _asInt(json['product_master_id']),
    productName: json['product_name'] as String? ?? '',
    variantId: _asNullableInt(json['variant_id']),
    variantName: json['variant_name'] as String?,
    shopProductId: _asNullableInt(json['shop_product_id']),
    quantity: _asInt(json['quantity']),
    price: _asDouble(json['price']),
    totalPrice: _asDouble(json['total_price']),
    imageUrl: json['image_url'] as String?,
    itemStatus: json['item_status'] as String? ?? 'PENDING',
  );
}

class Order {
  final int id;
  final String orderNumber;
  final int userId;
  final int? customerId;
  final int shopId;
  final OrderStatus status;
  final String? paymentMethod;
  final PaymentStatus paymentStatus;
  final String currency;
  final double subtotalAmount;
  final double deliveryFee;
  final double discountAmount;
  final double taxAmount;
  final double totalAmount;
  final int totalItems;
  final String? notes;
  final String? shippingAddressJson;
  final DateTime? placedAt;
  final DateTime? confirmedAt;
  final DateTime? preparingAt;
  final DateTime? readyAt;
  final DateTime? outForDeliveryAt;
  final DateTime? deliveredAt;
  final DateTime? cancelledAt;
  final int? cancelledBy;
  final String? cancelReason;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<OrderItem> items;

  const Order({
    required this.id,
    required this.orderNumber,
    required this.userId,
    this.customerId,
    required this.shopId,
    this.status = OrderStatus.pending,
    this.paymentMethod,
    this.paymentStatus = PaymentStatus.pending,
    this.currency = 'INR',
    this.subtotalAmount = 0,
    this.deliveryFee = 0,
    this.discountAmount = 0,
    this.taxAmount = 0,
    this.totalAmount = 0,
    this.totalItems = 0,
    this.notes,
    this.shippingAddressJson,
    this.placedAt,
    this.confirmedAt,
    this.preparingAt,
    this.readyAt,
    this.outForDeliveryAt,
    this.deliveredAt,
    this.cancelledAt,
    this.cancelledBy,
    this.cancelReason,
    required this.createdAt,
    required this.updatedAt,
    this.items = const [],
  });

  factory Order.fromJson(Map<String, dynamic> json) => Order(
    id: _asInt(json['id']),
    orderNumber: json['order_number'] as String? ?? '',
    userId: _asInt(json['user_id']),
    customerId: _asNullableInt(json['customer_id']),
    shopId: _asInt(json['shop_id']),
    status: OrderStatus.fromValue(json['status'] as String?),
    paymentMethod: json['payment_method'] as String?,
    paymentStatus: PaymentStatus.fromValue(json['payment_status'] as String?),
    currency: json['currency'] as String? ?? 'INR',
    subtotalAmount: _asDouble(json['subtotal_amount']),
    deliveryFee: _asDouble(json['delivery_fee']),
    discountAmount: _asDouble(json['discount_amount']),
    taxAmount: _asDouble(json['tax_amount']),
    totalAmount: _asDouble(json['total_amount']),
    totalItems: _asInt(json['total_items']),
    notes: json['notes'] as String?,
    shippingAddressJson: json['shipping_address_json'] as String?,
    placedAt: _asDateTime(json['placed_at']),
    confirmedAt: _asDateTime(json['confirmed_at']),
    preparingAt: _asDateTime(json['preparing_at']),
    readyAt: _asDateTime(json['ready_at']),
    outForDeliveryAt: _asDateTime(json['out_for_delivery_at']),
    deliveredAt: _asDateTime(json['delivered_at']),
    cancelledAt: _asDateTime(json['cancelled_at']),
    cancelledBy: _asNullableInt(json['cancelled_by']),
    cancelReason: json['cancel_reason'] as String?,
    createdAt:
        _asDateTime(json['created_at']) ??
        DateTime.fromMillisecondsSinceEpoch(0),
    updatedAt:
        _asDateTime(json['updated_at']) ??
        DateTime.fromMillisecondsSinceEpoch(0),
    items: (json['items'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(OrderItem.fromJson)
        .toList(growable: false),
  );
}

class OrderCreate {
  final int shopId;
  final String? shippingAddressJson;
  final String? notes;
  final double deliveryFee;
  final double discountAmount;
  final double taxAmount;
  final List<OrderItemCreate> items;

  const OrderCreate({
    required this.shopId,
    this.shippingAddressJson,
    this.notes,
    this.deliveryFee = 0,
    this.discountAmount = 0,
    this.taxAmount = 0,
    required this.items,
  });

  Map<String, dynamic> toJson() => {
    'shop_id': shopId,
    if (shippingAddressJson != null)
      'shipping_address_json': shippingAddressJson,
    if (notes != null) 'notes': notes,
    'delivery_fee': deliveryFee,
    'discount_amount': discountAmount,
    'tax_amount': taxAmount,
    'items': items.map((item) => item.toJson()).toList(growable: false),
  };
}

class OrderItemCreate {
  final int productMasterId;
  final String productName;
  final int? variantId;
  final String? variantName;
  final int? shopProductId;
  final int quantity;
  final double price;
  final String? imageUrl;

  const OrderItemCreate({
    required this.productMasterId,
    required this.productName,
    this.variantId,
    this.variantName,
    this.shopProductId,
    required this.quantity,
    required this.price,
    this.imageUrl,
  });

  Map<String, dynamic> toJson() => {
    'product_master_id': productMasterId,
    'product_name': productName,
    if (variantId != null) 'variant_id': variantId,
    if (variantName != null) 'variant_name': variantName,
    if (shopProductId != null) 'shop_product_id': shopProductId,
    'quantity': quantity,
    'price': price,
    if (imageUrl != null) 'image_url': imageUrl,
  };
}

class OrderStatusUpdate {
  final String status;
  final String? note;
  final int? processedBy;

  const OrderStatusUpdate({required this.status, this.note, this.processedBy});

  Map<String, dynamic> toJson() => {
    'status': status,
    if (note != null) 'note': note,
    if (processedBy != null) 'processed_by': processedBy,
  };
}

class OrderListResponse {
  final List<Order> orders;
  final int total;
  final int page;
  final int pageSize;
  final bool hasNext;

  const OrderListResponse({
    this.orders = const [],
    required this.total,
    required this.page,
    required this.pageSize,
    this.hasNext = false,
  });

  factory OrderListResponse.fromJson(Map<String, dynamic> json) =>
      OrderListResponse(
        orders: (json['orders'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(Order.fromJson)
            .toList(growable: false),
        total: _asInt(json['total']),
        page: _asInt(json['page']),
        pageSize: _asInt(json['page_size']),
        hasNext: json['has_next'] as bool? ?? false,
      );
}

int _asInt(Object? value) => value is num ? value.toInt() : 0;

int? _asNullableInt(Object? value) => value == null ? null : _asInt(value);

double _asDouble(Object? value) => value is num ? value.toDouble() : 0;

DateTime? _asDateTime(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
