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
  Future<OrderListResponse> listOrders({
    int? limit,
    int? offset,
  }) async {
    final data = await _apiClient.get(
      ApiEndpoints.myOrders,
      queryParameters: {
        'limit': ?limit,
        'offset': ?offset,
      },
    );
    return OrderListResponse.fromJson(Map<String, dynamic>.from(data as Map));
  }

  @override
  Future<Order> updateOrderStatus(String orderId, OrderStatusUpdate update) async {
    final data = await _apiClient.put(
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
    final data = await _apiClient.get(ApiEndpoints.trackOrder(orderId));
    return Order.fromJson(Map<String, dynamic>.from(data as Map));
  }
}
