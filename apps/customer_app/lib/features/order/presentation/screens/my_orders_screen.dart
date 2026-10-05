import 'package:flutter/material.dart';
import 'package:hyperlocal_app/core/utils/app_datetime.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/empty_state_view.dart';
import '../../../../core/widgets/skeletons.dart';
import '../../../../core/widgets/slow_load_notice.dart';
import '../../domain/models/order_models.dart';
import '../controllers/order_controller.dart';
import '../order_status_ui.dart';

/// Customer order history — every order placed by the signed-in customer,
/// newest first, with a one-tap jump into live status tracking.
class MyOrdersScreen extends ConsumerStatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  ConsumerState<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends ConsumerState<MyOrdersScreen> {
  Future<void> _refresh() async {
    ref.invalidate(myOrdersProvider);
    await ref.read(myOrdersProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(myOrdersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Orders'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
        ],
      ),
      body: ordersAsync.when(
        data: (orders) {
          if (orders.isEmpty) {
            return const EmptyStateView(
              icon: Icons.receipt_long_outlined,
              title: 'No orders yet',
              message: 'Orders you place will show up here for tracking.',
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: orders.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) => _OrderCard(order: orders[index]),
            ),
          );
        },
        // Matches the rows that are arriving: the layout does not jump when
        // the list lands, and a still-hung load past the threshold explains
        // itself with a retry instead of spinning unexplained.
        // ORDER cards, not product cards — no image, and a status pill where the
        // product row's third line would be.
        loading: () => Column(
          children: [
            const Expanded(
              child: SkeletonList(
                itemCount: 4,
                shape: SkeletonRowShape.order,
              ),
            ),
            SlowLoadNotice(
              message: 'Your orders are taking longer to load.',
              onRetry: _refresh,
            ),
          ],
        ),
        error: (err, st) => EmptyStateView(
          icon: Icons.error_outline,
          title: 'Could not load orders',
          message: err.toString(),
          actionLabel: 'Retry',
          onActionTap: _refresh,
        ),
      ),
    );
  }
}

/// Summary card for a single order in the history list.
class _OrderCard extends StatelessWidget {
  final Order order;

  const _OrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placed = order.placedAt ?? order.createdAt;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/order/${order.id}'),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      order.orderNumber,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _StatusChip(status: order.status),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                AppDateTime.formatDateTime(placed),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  const Icon(
                    Icons.shopping_bag_outlined,
                    size: 16,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    '${order.totalItems} '
                    '${order.totalItems == 1 ? 'item' : 'items'}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const Spacer(),
                  Text(
                    _money(order.totalAmount, order.currency),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact status pill shared by the list and detail screens.
class _StatusChip extends StatelessWidget {
  final OrderStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = status.color;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 14, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(
            status.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Formats an amount using the order's currency code (`INR` → `₹`).
String _money(double amount, String currency) {
  final symbol = currency == 'INR' ? '\u20B9' : '$currency ';
  return '$symbol${amount.toStringAsFixed(2)}';
}
