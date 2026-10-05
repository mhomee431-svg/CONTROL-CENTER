import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../domain/models/order_models.dart';
import '../domain/order_repository.dart';

/// Live backend implementation of [OrderRepository].
///
/// All reads/writes flow through [ApiClient], which unwraps the common
/// `{success, message, data}` envelope and maps Dio errors to [ApiException].
class ApiOrderRepository implements OrderRepository {
  final ApiClient _apiClient;

  ApiOrderRepository(this._apiClient);

  @override
  Future<Order> createOrder(OrderCreate order) async {
    final data = await _apiClient.post(
      ApiEndpoints.orders,
      data: order.toJson(),
    );
    return Order.fromJson(Map<String, dynamic>.from(data as Map));
  }

  @override
  Future<Order> getOrderById(String orderId) async {
    final data = await _apiClient.get(ApiEndpoints.orderById(orderId));
    return Order.fromJson(Map<String, dynamic>.from(data as Map));
  }

  @override
  Future<OrderListResponse> listOrders({int? limit, int? offset}) async {
    // The customer list is GET /orders (paginated). `page` is 1-based and
    // derived from the offset, mirroring OrderListResponse's page/page_size
    // contract. The backend defaults (page=1, page_size=20) apply when no
    // window is given.
    final data = await _apiClient.get(
      ApiEndpoints.orders,
      queryParameters: {
        // Null-aware element: an absent limit is omitted from the query rather
        // than sent as null, so the backend applies its own default page size.
        'page_size': ?limit,
        if (offset != null && limit != null && limit > 0)
          'page': (offset ~/ limit) + 1,
      },
    );
    return OrderListResponse.fromJson(Map<String, dynamic>.from(data as Map));
  }

  @override
  Future<Order> updateOrderStatus(
    String orderId,
    OrderStatusUpdate update,
  ) async {
    // Admin-only transition (POST /orders/{id}/status, require_admin). The
    // customer app keeps the contract member for interface completeness, but
    // the call is expected to be refused for a shopper — surfacing the refusal
    // is the honest behaviour, not hiding the capability.
    final data = await _apiClient.post(
      ApiEndpoints.updateOrderStatus(orderId),
      data: update.toJson(),
    );
    return Order.fromJson(Map<String, dynamic>.from(data as Map));
  }

  @override
  Future<Order> cancelOrder(String orderId) async {
    final data = await _apiClient.post(ApiEndpoints.cancelOrder(orderId));
    return Order.fromJson(Map<String, dynamic>.from(data as Map));
  }

  @override
  Future<Order> trackOrder(String orderId) async {
    // No dedicated tracking endpoint exists: the live order detail
    // (GET /orders/{id}, with status + timestamps + line items) IS the
    // tracking payload, so tracking reads through the detail route.
    final data = await _apiClient.get(ApiEndpoints.orderById(orderId));
    return Order.fromJson(Map<String, dynamic>.from(data as Map));
  }
}
