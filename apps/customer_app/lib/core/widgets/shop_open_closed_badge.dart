import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Renders a shop's open/closed state from the backend's opening-hours verdict.
///
/// Three distinct outcomes, and the third is the important one:
/// * `isOpenNow == true`  → "Open" (or "Open · No orders" when the shop is
///   trading but has stopped accepting orders).
/// * `isOpenNow == false` → "Closed".
/// * `isOpenNow == null`  → **nothing is rendered.** An unreported state is not
///   evidence that the shop is open, so the badge simply disappears rather
///   than defaulting to a reassuring "Open".
///
/// [acceptingOrders] is only consulted when the shop is open, and a null value
/// there is treated as unknown rather than "not accepting".
class ShopOpenClosedBadge extends StatelessWidget {
  /// The backend's verdict: true = open, false = closed, null = not reported.
  final bool? isOpenNow;

  /// Whether the shop is taking orders. Null = not reported.
  final bool? acceptingOrders;

  /// Compact styling for dense list rows (nearby shops, search results).
  final bool dense;

  const ShopOpenClosedBadge({
    super.key,
    required this.isOpenNow,
    this.acceptingOrders,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    // Unknown state renders nothing — never guess "Open".
    if (isOpenNow == null) return const SizedBox.shrink();

    final open = isOpenNow!;

    // Open-but-not-accepting is a real, distinct state worth surfacing: the
    // customer can visit but cannot order ahead.
    final String label;
    if (!open) {
      label = 'Closed';
    } else if (acceptingOrders == false) {
      label = 'Open · No orders';
    } else {
      label = 'Open';
    }

    final color = open
        ? (acceptingOrders == false
              ? Colors.orange.shade800
              : AppColors.secondary)
        : AppColors.error;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 5 : 6,
        vertical: dense ? 1 : 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: dense ? 10 : 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
