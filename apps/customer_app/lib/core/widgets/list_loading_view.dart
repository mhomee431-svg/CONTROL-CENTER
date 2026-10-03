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

  const ListLoadingView({super.key, this.message, this.onRetry, this.rows = 4});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: SkeletonList(itemCount: rows)),
        if (message != null)
          SlowLoadNotice(message: message!, onRetry: onRetry)
        else
          const SlowLoadNotice(message: 'Still loading…'),
      ],
    );
  }
}
