import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/env/env_config.dart';
import '../../../core/network/api_client.dart';
import '../data/api_order_repository.dart';
import 'models/order_models.dart';

/// Customer-facing order feature repository.
abstract class OrderRepository {
  Future<Order> createOrder(OrderCreate order);
  Future<Order> getOrderById(String orderId);
  Future<OrderListResponse> listOrders({int? limit, int? offset});
  Future<Order> updateOrderStatus(String orderId, OrderStatusUpdate update);
  Future<Order> cancelOrder(String orderId);
  Future<Order> trackOrder(String orderId);
}

/// Provider that wires the live [ApiOrderRepository] (when an API base URL
/// is configured) or a no-op throw for environments without a backend.
final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  if (!EnvConfig.hasApiBaseUrl) {
    throw UnsupportedError(
      'OrderRepository has no mock implementation; '
      'configure EnvConfig.hasApiBaseUrl to use the live backend.',
    );
  }
  return ApiOrderRepository(ref.watch(apiClientProvider));
});
