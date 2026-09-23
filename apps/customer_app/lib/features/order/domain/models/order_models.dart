import 'package:freezed_annotation/freezed_annotation.dart';

part 'order_models.freezed.dart';
part 'order_models.g.dart';

/// Order lifecycle states — must match the backend `OrderStatus` enum
/// (see `backend/app/models/order.py:OrderStatus`).
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

  static OrderStatus fromValue(String value) => values.firstWhere(
        (e) => e.value == value,
        orElse: () => OrderStatus.pending,
      );
}

/// Payment states — must match the backend `PaymentStatus` enum.
enum PaymentStatus {
  pending('PENDING'),
  paid('PAID'),
  failed('FAILED'),
  refunded('REFUNDED'),
  partiallyRefunded('PARTIALLY_REFUNDED');

  final String value;
  const PaymentStatus(this.value);
}

/// A single line item in an order. Price is a snapshot taken at checkout
/// time so historical orders never drift with catalog changes.
@freezed
class OrderItem with _$OrderItem {
  const factory OrderItem({
    required int id,
    required int orderId,
    required int productMasterId,
    required String productName,
    int? variantId,
    String? variantName,
    int? shopProductId,
    required int quantity,
    required double price,
    required double totalPrice,
    String? imageUrl,
    @Default('PENDING') String itemStatus,
  }) = _OrderItem;

  factory OrderItem.fromJson(Map<String, dynamic> json) =>
      _$OrderItemFromJson(json);
}

/// A customer checkout against a single shop. Mirrors the backend
/// `Order` model fields used by the API contract (SS 30-32).
@freezed
class Order with _$Order {
  const factory Order({
    required int id,
    required String orderNumber,
    required int userId,
    int? customerId,
    required int shopId,
    @Default(OrderStatus.pending) OrderStatus status,
    String? paymentMethod,
    @Default(PaymentStatus.pending) PaymentStatus paymentStatus,
    @Default('INR') String currency,
    @Default(0) double subtotalAmount,
    @Default(0) double deliveryFee,
    @Default(0) double discountAmount,
    @Default(0) double taxAmount,
    @Default(0) double totalAmount,
    @Default(0) int totalItems,
    String? notes,
    String? shippingAddressJson,
    DateTime? placedAt,
    DateTime? confirmedAt,
    DateTime? preparingAt,
    DateTime? readyAt,
    DateTime? outForDeliveryAt,
    DateTime? deliveredAt,
    DateTime? cancelledAt,
    int? cancelledBy,
    String? cancelReason,
    required DateTime createdAt,
    required DateTime updatedAt,
    @Default(<OrderItem>[]) List<OrderItem> items,
  }) = _Order;

  factory Order.fromJson(Map<String, dynamic> json) => _$OrderFromJson(json);
}

/// Request body for creating a new order (customer checkout).
@freezed
class OrderCreate with _$OrderCreate {
  const factory OrderCreate({
    required int shopId,
    String? shippingAddressJson,
    String? notes,
    @Default(0) double deliveryFee,
    @Default(0) double discountAmount,
    @Default(0) double taxAmount,
    required List<OrderItemCreate> items,
  }) = _OrderCreate;

  factory OrderCreate.fromJson(Map<String, dynamic> json) =>
      _$OrderCreateFromJson(json);
}

/// A line item in a create-order request. Price is the customer-facing
/// unit price snapshot from the cart.
@freezed
class OrderItemCreate with _$OrderItemCreate {
  const factory OrderItemCreate({
    required int productMasterId,
    required String productName,
    int? variantId,
    String? variantName,
    int? shopProductId,
    required int quantity,
    required double price,
    String? imageUrl,
  }) = _OrderItemCreate;

  factory OrderItemCreate.fromJson(Map<String, dynamic> json) =>
      _$OrderItemCreateFromJson(json);
}

/// Admin-driven status transition (SS 30-31).
@freezed
class OrderStatusUpdate with _$OrderStatusUpdate {
  const factory OrderStatusUpdate({
    required String status,
    String? note,
    int? processedBy,
  }) = _OrderStatusUpdate;

  factory OrderStatusUpdate.fromJson(Map<String, dynamic> json) =>
      _$OrderStatusUpdateFromJson(json);
}

/// Paginated list of orders.
@freezed
class OrderListResponse with _$OrderListResponse {
  const factory OrderListResponse({
    @Default(<Order>[]) List<Order> orders,
    required int total,
    required int page,
    required int pageSize,
    @Default(false) bool hasNext,
  }) = _OrderListResponse;

  factory OrderListResponse.fromJson(Map<String, dynamic> json) =>
      _$OrderListResponseFromJson(json);
}
