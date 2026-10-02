import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/empty_state_view.dart';
import '../../../../core/widgets/network_image_view.dart';
import '../../domain/models/order_models.dart';
import '../controllers/order_controller.dart';
import '../order_status_ui.dart';

/// Live tracking view for a single order: status timeline, line items,
/// bill breakdown, delivery address and a cancel action while the order is
/// still cancellable (mirrors the backend `is_cancellable` rule).

class OrderDetailScreen extends ConsumerWidget {
  final String orderId;

  const OrderDetailScreen({super.key, required this.orderId});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(orderDetailProvider(orderId));
    await ref.read(orderDetailProvider(orderId).future);
  }

  Future<void> _confirmCancel(
    BuildContext context,
    WidgetRef ref,
    Order order,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this order?'),
        content: Text(
          'Order ${order.orderNumber} will be cancelled. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep order'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final cancelled = await ref
        .read(cancelOrderControllerProvider.notifier)
        .cancel(orderId);

    if (!context.mounted) return;
    if (cancelled == null) {
      final error = ref.read(cancelOrderControllerProvider).error;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not cancel order: $error')));
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Order cancelled.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderAsync = ref.watch(orderDetailProvider(orderId));
    final cancelState = ref.watch(cancelOrderControllerProvider);
    final isCancelling = cancelState.isLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => _refresh(ref),
          ),
        ],
      ),
      body: orderAsync.when(
        data: (order) => RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              _StatusHeader(order: order),
              const SizedBox(height: AppSpacing.md),
              if (order.status.isTerminal)
                _TerminalBanner(order: order)
              else
                _ProgressTracker(order: order),
              const SizedBox(height: AppSpacing.md),
              _ItemsCard(order: order),
              const SizedBox(height: AppSpacing.md),
              _BillCard(order: order),
              const SizedBox(height: AppSpacing.md),
              _AddressCard(addressJson: order.shippingAddressJson),
              if (_isCancellable(order.status)) ...[
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: isCancelling
                      ? null
                      : () => _confirmCancel(context, ref, order),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.error,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: isCancelling
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.cancel_outlined),
                  label: Text(isCancelling ? 'Cancelling…' : 'Cancel order'),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
        loading: () =>
            const Center(child: CircularProgressIndicator.adaptive()),
        error: (err, st) => EmptyStateView(
          icon: Icons.error_outline,
          title: 'Could not load this order',
          message: err.toString(),
          actionLabel: 'Retry',
          onActionTap: () => _refresh(ref),
        ),
      ),
    );
  }
}

/// Cancellable while the order has not entered fulfilment hand-off — mirrors
/// `Order.is_cancellable` in the backend model.
bool _isCancellable(OrderStatus status) =>
    status == OrderStatus.pending ||
    status == OrderStatus.confirmed ||
    status == OrderStatus.preparing;

/// Formats an amount using the order's currency code (`INR` → `₹`).
///
/// Mirrors the file-private helper in `my_orders_screen.dart` (Dart library
/// privacy keeps each screen's helper independent).
String _money(double amount, String currency) {
  final symbol = currency == 'INR' ? '\u20B9' : '$currency ';
  return '$symbol${amount.toStringAsFixed(2)}';
}

/// Order number, live status pill, payment state and placed timestamp.
class _StatusHeader extends StatelessWidget {
  final Order order;

  const _StatusHeader({required this.order});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placed = order.placedAt ?? order.createdAt;

    return Card(
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
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: order.status.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        order.status.icon,
                        size: 14,
                        color: order.status.color,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        order.status.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: order.status.color,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Placed ${DateFormat('d MMM yyyy, h:mm a').format(placed.toLocal())}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(
                  Icons.payments_outlined,
                  size: 16,
                  color: order.paymentStatus.color,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  order.paymentStatus.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: order.paymentStatus.color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (order.paymentMethod != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '• ${order.paymentMethod}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
            if (order.notes != null && order.notes!.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Note: ${order.notes}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Vertical progress tracker across the forward-only fulfilment chain.
class _ProgressTracker extends StatelessWidget {
  final Order order;

  const _ProgressTracker({required this.order});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentIndex = order.status.chainIndex;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Order progress',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (var i = 0; i < orderFulfilmentChain.length; i++)
              _TrackerStep(
                status: orderFulfilmentChain[i],
                isDone: currentIndex >= 0 && i < currentIndex,
                isCurrent: i == currentIndex,
                isLast: i == orderFulfilmentChain.length - 1,
                timestamp: _timestampFor(order, orderFulfilmentChain[i]),
              ),
          ],
        ),
      ),
    );
  }

  /// Best-effort timestamp for the step, when the backend recorded one.
  DateTime? _timestampFor(Order order, OrderStatus status) {
    return switch (status) {
      OrderStatus.pending => order.placedAt,
      OrderStatus.confirmed => order.confirmedAt,
      OrderStatus.preparing => order.preparingAt,
      OrderStatus.readyForPickup => order.readyAt,
      OrderStatus.outForDelivery => order.outForDeliveryAt,
      OrderStatus.delivered => order.deliveredAt,
      _ => null,
    };
  }
}

/// A single row of the vertical progress tracker.
class _TrackerStep extends StatelessWidget {
  final OrderStatus status;
  final bool isDone;
  final bool isCurrent;
  final bool isLast;
  final DateTime? timestamp;

  const _TrackerStep({
    required this.status,
    required this.isDone,
    required this.isCurrent,
    required this.isLast,
    this.timestamp,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = isDone || isCurrent;
    final color = active ? status.color : AppColors.textMuted;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active
                      ? color.withValues(alpha: 0.15)
                      : Colors.transparent,
                  border: Border.all(color: color, width: 2),
                ),
                child: isDone
                    ? Icon(Icons.check, size: 13, color: color)
                    : isCurrent
                    ? Center(
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: color,
                          ),
                        ),
                      )
                    : null,
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: isDone
                        ? color
                        : AppColors.textMuted.withValues(alpha: 0.3),
                  ),
                ),
            ],
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: active ? AppColors.textLight : AppColors.textMuted,
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  if (timestamp != null)
                    Text(
                      DateFormat('d MMM, h:mm a').format(timestamp!.toLocal()),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Banner shown instead of the tracker for cancelled/refunded/failed orders.
class _TerminalBanner extends StatelessWidget {
  final Order order;

  const _TerminalBanner({required this.order});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = order.status.color;

    return Card(
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(order.status.icon, color: color),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.status.label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (order.cancelReason != null &&
                      order.cancelReason!.trim().isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(order.cancelReason!, style: theme.textTheme.bodySmall),
                  ],
                  if (order.cancelledAt != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      DateFormat('d MMM yyyy, h:mm a')
                          .format(order.cancelledAt!.toLocal()),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Line items with checkout-time price snapshots.
class _ItemsCard extends StatelessWidget {
  final Order order;

  const _ItemsCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Items (${order.totalItems})',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (order.items.isEmpty)
              Text(
                'No line items on this order.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textMuted,
                ),
              )
            else
              for (final item in order.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.backgroundLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child:
                            item.imageUrl != null && item.imageUrl!.isNotEmpty
                            ? NetworkImageView(
                                // Without the explicit size the decode cannot be
                                // bounded, so a 4000px photo is decoded for a
                                // 44px slot and every line of the order re-decodes
                                // it on scroll.
                                imageUrl: item.imageUrl,
                                width: 44,
                                height: 44,
                                borderRadius: 8,
                              )
                            : const Icon(
                                Icons.shopping_bag_outlined,
                                size: 20,
                                color: AppColors.textMuted,
                              ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.productName,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (item.variantName != null &&
                                item.variantName!.isNotEmpty)
                              Text(
                                item.variantName!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.textMuted,
                                ),
                              ),
                            Text(
                              '${item.quantity} × '
                              '${_money(item.price, order.currency)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _money(item.totalPrice, order.currency),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// Subtotal → delivery → tax → discount → total breakdown.
class _BillCard extends StatelessWidget {
  final Order order;

  const _BillCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bill details',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _BillRow(
              label: 'Subtotal',
              value: _money(order.subtotalAmount, order.currency),
            ),
            _BillRow(
              label: 'Delivery fee',
              value: _money(order.deliveryFee, order.currency),
            ),
            if (order.taxAmount > 0)
              _BillRow(
                label: 'Taxes',
                value: _money(order.taxAmount, order.currency),
              ),
            if (order.discountAmount > 0)
              _BillRow(
                label: 'Discount',
                value: '-${_money(order.discountAmount, order.currency)}',
                valueColor: AppColors.secondary,
              ),
            const Divider(height: AppSpacing.lg),
            _BillRow(
              label: 'Total',
              value: _money(order.totalAmount, order.currency),
              isTotal: true,
            ),
          ],
        ),
      ),
    );
  }
}

/// One label/value line in the bill breakdown.
class _BillRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isTotal;
  final Color? valueColor;

  const _BillRow({
    required this.label,
    required this.value,
    this.isTotal = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = isTotal
        ? theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)
        : theme.textTheme.bodyMedium?.copyWith(color: AppColors.textMuted);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: style),
          const Spacer(),
          Text(
            value,
            style: isTotal
                ? style
                : style?.copyWith(color: valueColor ?? AppColors.textLight),
          ),
        ],
      ),
    );
  }
}

/// Delivery address snapshot captured at checkout time.
class _AddressCard extends StatelessWidget {
  final String? addressJson;

  const _AddressCard({required this.addressJson});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = _summarise(addressJson);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.location_on_outlined,
              size: 20,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Delivery address',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    summary ?? 'No address recorded for this order.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Renders the checkout address snapshot; tolerates both a JSON object and a
  /// plain-text snapshot without throwing.
  String? _summarise(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final parts = <String>[
          for (final key in const [
            'label',
            'address_line1',
            'address_line2',
            'landmark',
            'city',
            'state',
            'pincode',
          ])
            if (decoded[key] != null &&
                decoded[key].toString().trim().isNotEmpty)
              decoded[key].toString().trim(),
        ];
        if (parts.isNotEmpty) return parts.join(', ');
      }
    } catch (_) {
      // Not JSON — fall through and show the raw snapshot.
    }
    return raw;
  }
}
