import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/order_models.dart';
import '../../domain/order_repository.dart';

/// The signed-in customer's order history (server-ordered, newest first).
final myOrdersProvider = FutureProvider.autoDispose<List<Order>>((ref) async {
  final repo = ref.watch(orderRepositoryProvider);
  final response = await repo.listOrders();
  return response.orders;
});

/// A single order with its live status, timestamps and line items.
final orderDetailProvider = FutureProvider.autoDispose.family<Order, String>((
  ref,
  orderId,
) async {
  final repo = ref.watch(orderRepositoryProvider);
  return repo.getOrderById(orderId);
});

/// Cancel-order action controller.
///
/// Tracks the in-flight [AsyncValue] so the UI can disable the action button
/// and surface failures without discarding the loaded order.
final cancelOrderControllerProvider =
    NotifierProvider<CancelOrderController, AsyncValue<Order?>>(
      CancelOrderController.new,
    );

class CancelOrderController extends Notifier<AsyncValue<Order?>> {
  @override
  AsyncValue<Order?> build() => const AsyncData<Order?>(null);

  /// Requests cancellation; returns the cancelled order or `null` on failure.
  Future<Order?> cancel(String orderId) async {
    state = const AsyncLoading<Order?>();
    final repo = ref.read(orderRepositoryProvider);
    try {
      final cancelled = await repo.cancelOrder(orderId);
      state = AsyncData<Order?>(cancelled);
      // Both the history list and the detail view are now stale.
      ref.invalidate(myOrdersProvider);
      ref.invalidate(orderDetailProvider(orderId));
      return cancelled;
    } catch (e, st) {
      state = AsyncError<Order?>(e, st);
      return null;
    }
  }

  /// Clears a previous success/error so the next action starts clean.
  void reset() => state = const AsyncData<Order?>(null);
}
