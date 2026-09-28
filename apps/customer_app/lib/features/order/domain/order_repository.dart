import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/env/env_config.dart';
import '../../../core/network/api_client.dart';
import '../data/api_order_repository.dart';
import '../data/mock_order_repository.dart';
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

/// Provider that wires the live [ApiOrderRepository] when an API base URL is
/// configured, or an in-memory [MockOrderRepository] when it is not.
///
/// This previously threw `UnsupportedError` without a backend. A provider that
/// throws on read takes down its whole route subtree, so the customer could not
/// even open the orders screen — strictly worse than showing local demo data.
final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  if (!EnvConfig.hasApiBaseUrl) {
    // Dev/demo build with no backend: local demo orders keep the feature
    // usable. Staging and production always resolve to the live API (per the
    // build-time environment profile), so a mock cannot leak into a release.
    return MockOrderRepository();
  }
  return ApiOrderRepository(ref.watch(apiClientProvider));
});
