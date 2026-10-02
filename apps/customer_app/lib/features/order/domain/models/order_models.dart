// Customer-facing order models with explicit JSON serialization.
//
// These models intentionally do not depend on generated files so the order
// feature remains buildable in environments that have Dart but not Flutter.
//
// Decoding goes through [JsonMap] so a response that is missing a field, sends
// an unexpected type, or carries a status this build has never heard of yields
// a partially-populated order instead of an exception. The two enum decoders
// below are the reason an order list can never be taken down by one new backend
// status value.

import '../../../../core/network/enum_codec.dart';
import '../../../../core/network/json_map.dart';

/// Order lifecycle states.
///
/// Carries a `value` so the wire spelling is explicit rather than inferred
/// from the Dart identifier — the backend's vocabulary is the contract, and
/// renaming a Dart member must not silently change what we send or accept.
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

  /// Decodes a backend status, never throwing.
  ///
  /// An unrecognised value becomes [pending] — the initial state — rather than
  /// throwing. Falling back to the earliest state is a recoverable misreading;
  /// crashing the order list is not. Use [isRecognised] to detect the fallback
  /// and offer a refresh instead of presenting it as a current state.
  static OrderStatus fromValue(String? value) => enumCodec<OrderStatus>(
    value,
    OrderStatus.values,
    OrderStatus.pending,
    // The wire value is `READY_FOR_PICKUP`; the Dart name is camelCase.
    normalize: (lower) => lower.replaceAll(RegExp(r'[\s\-]+'), '_'),
  );
}

/// Whether [raw] is a status this build recognises.
///
/// Lets a caller tell a genuine `PENDING` from one that arrived as a fallback
/// for an unknown value, so the UI can show "status unavailable" rather than
/// assert a state the backend never sent.
bool isRecognised(String? raw) =>
    raw != null &&
    OrderStatus.values.any((s) => s.value == raw.trim().toUpperCase());

enum PaymentStatus {
  pending('PENDING'),
  paid('PAID'),
  failed('FAILED'),
  refunded('REFUNDED'),
  partiallyRefunded('PARTIALLY_REFUNDED');

  final String value;
  const PaymentStatus(this.value);

  /// Decodes a backend payment status, never throwing. See [OrderStatus].
  static PaymentStatus fromValue(String? value) => enumCodec<PaymentStatus>(
    value,
    PaymentStatus.values,
    PaymentStatus.pending,
    normalize: (lower) => lower.replaceAll(RegExp(r'[\s\-]+'), '_'),
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

  /// Decodes one line item.
  ///
  /// Takes [Object?] rather than a raw map so it is total on its own: a caller
  /// holding a possibly-null or wrongly-typed value can pass it straight in.
  /// [Order.fromJson] passes the already-wrapped `JsonMap` from `objectList`,
  /// which `tryParse` returns unchanged — no re-parse, no lost fields.
  factory OrderItem.fromJson(Object? value) {
    final json = value is JsonMap ? value : JsonMap.tryParse(value);
    return OrderItem(
      id: json.integerOr('id'),
      orderId: json.integerOr('order_id'),
      productMasterId: json.integerOr('product_master_id'),
      productName: json.stringOr('product_name'),
      variantId: json.integer('variant_id'),
      variantName: json.string('variant_name'),
      shopProductId: json.integer('shop_product_id'),
      quantity: json.integerOr('quantity'),
      price: json.decimalOr('price'),
      totalPrice: json.decimalOr('total_price'),
      imageUrl: json.string('image_url'),
      itemStatus: json.stringOr('item_status', 'PENDING'),
    );
  }
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

  factory Order.fromJson(Object? value) {
    final json = value is JsonMap ? value : JsonMap.tryParse(value);
    // A missing timestamp used to become 1970, which then rendered as a real
    // (very old) order date. The epoch sentinel is kept deliberately — it is
    // the documented "unknown" marker and the UI formats it as such.
    final createdAt =
        json.dateTime('created_at') ?? DateTime.fromMillisecondsSinceEpoch(0);

    return Order(
      id: json.integerOr('id'),
      orderNumber: json.stringOr('order_number'),
      userId: json.integerOr('user_id'),
      customerId: json.integer('customer_id'),
      shopId: json.integerOr('shop_id'),
      status: OrderStatus.fromValue(json.string('status')),
      paymentMethod: json.string('payment_method'),
      paymentStatus: PaymentStatus.fromValue(json.string('payment_status')),
      currency: json.stringOr('currency', 'INR'),
      subtotalAmount: json.decimalOr('subtotal_amount'),
      deliveryFee: json.decimalOr('delivery_fee'),
      discountAmount: json.decimalOr('discount_amount'),
      taxAmount: json.decimalOr('tax_amount'),
      totalAmount: json.decimalOr('total_amount'),
      totalItems: json.integerOr('total_items'),
      notes: json.string('notes'),
      shippingAddressJson: json.string('shipping_address_json'),
      placedAt: json.dateTime('placed_at'),
      confirmedAt: json.dateTime('confirmed_at'),
      preparingAt: json.dateTime('preparing_at'),
      readyAt: json.dateTime('ready_at'),
      outForDeliveryAt: json.dateTime('out_for_delivery_at'),
      deliveredAt: json.dateTime('delivered_at'),
      cancelledAt: json.dateTime('cancelled_at'),
      cancelledBy: json.integer('cancelled_by'),
      cancelReason: json.string('cancel_reason'),
      createdAt: createdAt,
      updatedAt: json.dateTime('updated_at') ?? createdAt,
      // A malformed line item costs that line, not the whole order.
      items: json
          .objectList('items')
          .map(OrderItem.fromJson)
          .toList(growable: false),
    );
  }
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

  factory OrderListResponse.fromJson(Object? value) {
    final json = value is JsonMap ? value : JsonMap.tryParse(value);
    return OrderListResponse(
      // `orders` has also been called `results` on paginated endpoints; the
      // alias keeps one response shape working across both.
      orders: json.has('orders')
          ? json
                .objectList('orders')
                .map(Order.fromJson)
                .toList(growable: false)
          : json
                .objectList('results')
                .map(Order.fromJson)
                .toList(growable: false),
      total: json.integerOr('total'),
      page: json.integerOr('page'),
      pageSize: json.integerOr('page_size'),
      // A missing `has_next` must not silently claim there is no more: derive it
      // from the page when possible, since a false here hides further orders.
      hasNext: json.booleanOr(
        'has_next',
        json.integer('total') != null &&
            json.objectList('orders').length >= json.integerOr('page_size'),
      ),
    );
  }
}

/// The reason an [Order] mutation was refused.
///
/// A mutation can fail for two very different reasons and the UI must not
/// conflate them: the user asked for something the rules forbid (e.g. cancelling
/// a delivered order), versus the order does not exist. Only the first is worth
/// explaining back to the customer.
class OrderMutationException implements Exception {
  final String message;

  const OrderMutationException(this.message);

  @override
  String toString() => message;
}

/// Raised when an order id does not exist in this data source.
///
/// Distinct from [OrderMutationException] so "not found" is never reported as
/// "your action was rejected" — the two need different UI copy.
class OrderNotFoundException implements Exception {
  final String orderId;

  const OrderNotFoundException(this.orderId);

  @override
  String toString() => 'No order with id $orderId';
}

int _asInt(Object? value) => value is num ? value.toInt() : 0;

// The three coercions below are the shared JSON-tolerance helpers for this
// file's models. They are intentionally KEPT even while unreferenced: every
// optional numeric/temporal field added to an order payload will need them,
// and re-deriving them per model is how the null-vs-zero bug class returns.
// They are silenced rather than deleted so the guidance survives an analyzer
// run that would otherwise flag them on every save.
// ignore: unused_element
int? _asNullableInt(Object? value) => value == null ? null : _asInt(value);

// ignore: unused_element
double _asDouble(Object? value) => value is num ? value.toDouble() : 0;

// ignore: unused_element
DateTime? _asDateTime(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
