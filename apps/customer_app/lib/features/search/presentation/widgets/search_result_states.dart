import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/skeletons.dart';
import '../../../../core/widgets/slow_load_notice.dart';

/// Reusable search state views for loading / empty / error.
/// Keeps state visuals consistent across the search journey.

/// The search loading state.
///
/// SKELETON, not a bare spinner. Search results are a list of offer cards, so
/// the skeleton is that list — the customer can see what is arriving and the
/// layout does not jump when it lands. The spinner is deliberately NOT kept
/// alongside it: two loading visuals at once is how a screen ends up looking
/// busier than the content it is waiting for.
///
/// [onRetry] is optional and only passed by callers who can actually re-issue
/// the request. When it is null the [SlowLoadNotice] still explains the wait
/// but offers no button, because a Retry that cannot retry is a dead control.
class SearchLoadingView extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;

  /// How many placeholder rows to draw. Three roughly fills a phone viewport
  /// without inviting the customer to scroll placeholders.
  final int skeletonRows;

  const SearchLoadingView({
    super.key,
    this.message,
    this.onRetry,
    this.skeletonRows = 3,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (message != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              0,
            ),
            child: Text(
              message!,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ),
        // Shrink-wrapped so the notice sits UNDER the skeleton rather than
        // pushing it off-screen: the placeholder is the main content.
        Flexible(
          child: SkeletonList(
            itemCount: skeletonRows,
            padding: const EdgeInsets.all(AppSpacing.md),
          ),
        ),
        SlowLoadNotice(
          message: 'This is taking longer than usual.',
          onRetry: onRetry,
        ),
      ],
    );
  }
}

class SearchEmptyView extends StatelessWidget {
  final String title;
  final String? message;
  final VoidCallback? onAction;
  final String? actionLabel;

  const SearchEmptyView({
    super.key,
    required this.title,
    this.message,
    this.onAction,
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 64, color: AppColors.textMuted),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted),
              ),
            ],
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class SearchErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const SearchErrorView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Something went wrong',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
