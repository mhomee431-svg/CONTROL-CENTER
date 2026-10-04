import 'package:flutter/material.dart';

import '../network/api_error_handler.dart';
import '../theme/app_theme.dart';
import 'skeletons.dart';

class StateViewBuilder<T> extends StatelessWidget {
  final bool isLoading;
  final ApiException? error;
  final List<T>? data;
  final Widget Function(BuildContext context, List<T> items) onSuccess;
  final VoidCallback onRetry;
  final String emptyTitle;
  final String emptyMessage;
  final IconData emptyIcon;

  const StateViewBuilder({
    super.key,
    required this.isLoading,
    required this.error,
    required this.data,
    required this.onSuccess,
    required this.onRetry,
    this.emptyTitle = 'No Items Found',
    this.emptyMessage = 'There are no items available right now.',
    this.emptyIcon = Icons.inbox_outlined,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      // A LIST of [T] is arriving, so the placeholder is a list of rows — not a
      // centred spinner. This used to render `CircularProgressIndicator` +
      // "Loading details...", which told the customer nothing about what was
      // coming and then made the whole screen re-layout when it arrived.
      // `product` is the right shape because the shape a caller passes here is
      // its own row shape; callers wanting a different one should reach for
      // `ListLoadingView`, which takes it explicitly.
      return const SkeletonList(itemCount: 4, shape: SkeletonRowShape.product);
    }

    if (error != null) {
      return _buildErrorView(context, error!);
    }

    if (data == null || data!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(emptyIcon, size: 64, color: AppColors.textMuted),
              const SizedBox(height: AppSpacing.md),
              Text(
                emptyTitle,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                emptyMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
      );
    }

    return onSuccess(context, data!);
  }

  Widget _buildErrorView(BuildContext context, ApiException apiError) {
    IconData icon = Icons.error_outline;
    String title = 'Something Went Wrong';

    switch (apiError.type) {
      case ApiErrorType.offline:
        icon = Icons.wifi_off_rounded;
        title = 'No Internet Connection';
        break;
      case ApiErrorType.timeout:
        icon = Icons.timer_off_outlined;
        title = 'Request Timed Out';
        break;
      case ApiErrorType.serverError:
        icon = Icons.dns_outlined;
        title = 'Server Error';
        break;
      case ApiErrorType.partialFailure:
        icon = Icons.sync_problem_rounded;
        title = 'Partial Failure';
        break;
      case ApiErrorType.sessionExpired:
        icon = Icons.lock_clock_outlined;
        title = 'Session Expired';
        break;
      case ApiErrorType.accessDenied:
        icon = Icons.block_rounded;
        title = 'Access Denied';
        break;
      case ApiErrorType.notFound:
        icon = Icons.search_off_rounded;
        title = 'Not Found';
        break;
      case ApiErrorType.conflict:
        icon = Icons.merge_rounded;
        title = 'Already Done';
        break;
      case ApiErrorType.validation:
        icon = Icons.rule_rounded;
        title = 'Check Your Details';
        break;
      case ApiErrorType.rateLimited:
        icon = Icons.hourglass_top_rounded;
        title = 'Too Many Attempts';
        break;
      default:
        break;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: AppColors.error),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              apiError.message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpacing.lg),
            // "Retry" is only offered when retrying could actually work. A
            // button on a 403/404/409 traps the customer on an action that can
            // never succeed; those cases get a way back into the app instead.
            if (apiError.isRetryable)
              ElevatedButton.icon(
                key: const Key('stateViewRetryButton'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              )
            else
              OutlinedButton.icon(
                key: const Key('stateViewBackButton'),
                onPressed: () {
                  // Popping is the escape hatch: it guarantees the customer is
                  // never stranded on a dead-end error screen.
                  final navigator = Navigator.of(context);
                  if (navigator.canPop()) {
                    navigator.pop();
                  }
                },
                icon: const Icon(Icons.arrow_back),
                label: const Text('Go back'),
              ),
          ],
        ),
      ),
    );
  }
}
