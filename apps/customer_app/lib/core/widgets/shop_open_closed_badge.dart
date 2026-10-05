import 'package:flutter/material.dart';

import '../../../../core/a11y/a11y.dart';
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

    // Two colours, on purpose: the vivid token paints the BACKGROUND and the ICON,
    // the accessible token paints the TEXT.
    //
    // A11y, measured: AppColors.warning as text on a near-white badge measures
    // 2.15:1, and AppColors.error 3.76:1 — both below the 4.5:1 AA threshold. So
    // the label that tells a customer whether the shop is trading was, in
    // measured terms, among the least readable text in the app. The `*Text`
    // tokens keep the same hues at a lightness that passes on a light surface
    // (5.02:1 and 4.83:1) while the chip still reads as a warning.
    final textColor = open
        ? (acceptingOrders == false
              ? AppColors.warningText
              : AppColors.successText)
        : AppColors.errorText;

    final color = open
        ? (acceptingOrders == false ? AppColors.warning : AppColors.secondary)
        : AppColors.error;

    // A11y: colour alone is not the signal.
    //
    // "Open" (green) vs "Closed" (red) is the textbook worst case for colour
    // vision deficiency, and a customer who cannot separate them is being told
    // the wrong thing about whether a shop is trading — a real-world cost, not
    // a cosmetic one. So the badge carries THREE independent signals: the
    // wording (always present), a shape (icon), and the colour. Remove any one
    // and the meaning still survives.
    final icon = open
        ? (acceptingOrders == false
              ? Icons.pause_circle_outline
              : Icons.check_circle_outline)
        : Icons.cancel_outlined;

    return Semantics(
      // Read as one phrase rather than as a stray glyph plus a stray word.
      label: label,
      excludeSemantics: true,
      // The badge is the flexible child of the card's title Row, so it must be
      // allowed to shrink. `Expanded` on the name and an unconstrained badge
      // means the badge lays out at its FULL intrinsic width and overflows the
      // row -- raising 12pt (the legibility floor) plus the icon made that
      // visible. Constraining the badge here is what makes the larger,
      // readable type actually fit.
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 132),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: dense ? 6 : 7,
            vertical: dense ? 3 : 4,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon only in the roomy variant.
              //
              // The ICON is the redundant, colour-free signal, but in a dense
              // list row there is no width for it. The WORD is the primary
              // non-colour signal and is always present in both variants, so
              // the requirement still holds in dense mode -- it just relies on
              // the label rather than on label-plus-shape.
              if (!dense) ...[
                A11y.decorative(Icon(icon, size: 13, color: color)),
                const SizedBox(width: 3),
              ],
              // Flexible so the label ellipsises rather than overflowing.
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    // Never below the legibility floor. 10pt was illegible on
                    // a cheap phone at arm's length, and a status a customer
                    // cannot read is not a status.
                    fontSize: A11y.minFontSize,
                    fontWeight: AppTypography.bold,
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
