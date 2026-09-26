import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/models/order_models.dart';

/// Forward-only fulfilment chain used to render the progress tracker.
/// Terminal states (cancelled/refunded/failed) are rendered separately.
const List<OrderStatus> orderFulfilmentChain = <OrderStatus>[
  OrderStatus.pending,
  OrderStatus.confirmed,
  OrderStatus.preparing,
  OrderStatus.readyForPickup,
  OrderStatus.outForDelivery,
  OrderStatus.delivered,
];

/// Presentation helpers for [OrderStatus] — keeps the label/colour/icon
/// mapping in one place so the list card and the detail tracker never drift.
extension OrderStatusUi on OrderStatus {
  String get label => switch (this) {
    OrderStatus.pending => 'Pending',
    OrderStatus.confirmed => 'Confirmed',
    OrderStatus.preparing => 'Preparing',
    OrderStatus.readyForPickup => 'Ready for pickup',
    OrderStatus.outForDelivery => 'Out for delivery',
    OrderStatus.delivered => 'Delivered',
    OrderStatus.cancelled => 'Cancelled',
    OrderStatus.refunded => 'Refunded',
    OrderStatus.failed => 'Failed',
  };

  IconData get icon => switch (this) {
    OrderStatus.pending => Icons.schedule,
    OrderStatus.confirmed => Icons.verified_outlined,
    OrderStatus.preparing => Icons.inventory_2_outlined,
    OrderStatus.readyForPickup => Icons.shopping_bag_outlined,
    OrderStatus.outForDelivery => Icons.local_shipping_outlined,
    OrderStatus.delivered => Icons.check_circle_outline,
    OrderStatus.cancelled => Icons.cancel_outlined,
    OrderStatus.refunded => Icons.currency_exchange,
    OrderStatus.failed => Icons.error_outline,
  };

  Color get color => switch (this) {
    OrderStatus.delivered => AppColors.secondary,
    OrderStatus.cancelled || OrderStatus.failed => AppColors.error,
    OrderStatus.refunded => AppColors.textMuted,
    _ => AppColors.primary,
  };

  /// True when the order will never progress further along the happy path.
  bool get isTerminal =>
      this == OrderStatus.cancelled ||
      this == OrderStatus.refunded ||
      this == OrderStatus.failed;

  /// Index of this status within [orderFulfilmentChain], or -1 for terminal
  /// states that are not part of the forward chain.
  int get chainIndex => orderFulfilmentChain.indexOf(this);
}

/// Presentation helpers for [PaymentStatus].
extension PaymentStatusUi on PaymentStatus {
  String get label => switch (this) {
    PaymentStatus.pending => 'Payment pending',
    PaymentStatus.paid => 'Paid',
    PaymentStatus.failed => 'Payment failed',
    PaymentStatus.refunded => 'Refunded',
    PaymentStatus.partiallyRefunded => 'Partially refunded',
  };

  Color get color => switch (this) {
    PaymentStatus.paid => AppColors.secondary,
    PaymentStatus.failed => AppColors.error,
    PaymentStatus.refunded ||
    PaymentStatus.partiallyRefunded => AppColors.textMuted,
    PaymentStatus.pending => AppColors.primary,
  };
}
