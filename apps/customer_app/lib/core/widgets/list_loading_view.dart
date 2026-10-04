import 'package:flutter/material.dart';

import 'skeletons.dart';
import 'slow_load_notice.dart';

/// The standard first-load state for a LIST-shaped screen.
///
/// WHY ONE WIDGET
/// --------------
/// Every list screen used to hand-roll `Center(child:
/// CircularProgressIndicator.adaptive())` — 15 of them, each implying that the
/// content arriving was unknowable, none of them bounded, and several of them
/// with no retry at all. A customer who watched one of those spin for twenty
/// seconds had no idea what was coming or whether anything could be done.
///
/// This is the replacement: a skeleton in the SHAPE of the rows, plus
/// [SlowLoadNotice] so the wait is bounded and explained. [onRetry] is optional
/// and should be omitted rather than faked — a Retry that cannot re-issue the
/// request is the dead control the error-handling rules forbid.
class ListLoadingView extends StatelessWidget {
  /// One honest line if the load outlasts the notice's threshold. Supply it:
  /// "taking longer than usual" with no subject is barely better than nothing.
  final String? message;

  /// Re-reads the list, or null when the caller has nothing to re-issue.
  final VoidCallback? onRetry;

  /// Placeholder rows. Four fits a phone viewport without inviting a scroll
  /// through placeholders.
  final int rows;

  /// The shape this screen's rows actually have.
  ///
  /// Required to be a deliberate choice per screen: the default matches a
  /// product card, which is right for the search and saved lists and wrong
  /// everywhere else. Passing it here rather than letting each screen build its
  /// own keeps the bounded [SlowLoadNotice] behaviour that every list screen
  /// depends on.
  final SkeletonRowShape shape;

  /// Overrides the row height [SkeletonRowShape] would use. Normally null —
  /// prefer letting the shape name its own height over repeating a magic number.
  final double? rowHeight;

  const ListLoadingView({
    super.key,
    this.message,
    this.onRetry,
    this.rows = 4,
    this.shape = SkeletonRowShape.product,
    this.rowHeight,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SkeletonList(itemCount: rows, shape: shape, rowHeight: rowHeight),
        ),
        if (message != null)
          SlowLoadNotice(message: message!, onRetry: onRetry)
        else
          const SlowLoadNotice(message: 'Still loading…'),
      ],
    );
  }
}
