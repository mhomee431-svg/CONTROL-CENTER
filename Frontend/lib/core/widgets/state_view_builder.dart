import 'package:flutter/material.dart';
import '../network/api_error_handler.dart';
import '../theme/app_theme.dart';

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
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator.adaptive(),
            SizedBox(height: AppSpacing.md),
            Text('Loading details...', style: TextStyle(color: AppColors.textMuted)),
          ],
        ),
      );
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
              Text(emptyTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.sm),
              Text(emptyMessage, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
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
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: AppSpacing.sm),
            Text(
              apiError.message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            )
          ],
        ),
      ),
    );
  }
}