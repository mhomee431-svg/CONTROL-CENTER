import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../location/presentation/controllers/location_controller.dart';
import '../../../../core/theme/app_theme.dart';

/// Shown when the customer's auto-detected location has no registered shops
/// yet. Gives them the option to enter a pin code manually to see shops
/// in that delivery area.
class ComingSoonScreen extends ConsumerWidget {
  const ComingSoonScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationState = ref.watch(locationControllerProvider);
    final location = locationState.location;

    // NOTE: intentionally NO Scaffold here. This widget is embedded inside the
    // HomeScreen's CustomScrollView (SliverToBoxAdapter) where an inner
    // Scaffold gets unbounded height and crashes layout ("RenderCustomMulti
    // ChildLayoutBox object was given an infinite size"). The /coming-soon
    // route wraps this widget in its own Scaffold.
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.rocket_launch,
              size: 90,
              color: AppColors.primary,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Coming Soon!',
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'We are expanding to your area.\n'
              'Enter your pin code to check if we have launched there.',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: AppColors.textMuted, height: 1.4),
              textAlign: TextAlign.center,
            ),
            if (location != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'Detected location: ${location.displayAddress}',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AppColors.primary),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            ElevatedButton(
              onPressed: () => _showPinDialog(context, ref),
              child: const Text('Manually write your area pin'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () {
                ref
                    .read(locationControllerProvider.notifier)
                    .fetchCurrentLocation(force: true);
              },
              child: const Text('Retry Location'),
            ),
          ],
        ),
      ),
    );
  }

  void _showPinDialog(BuildContext context, WidgetRef ref) {
    final TextEditingController pinController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enter Area Pin Code'),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Enter your 6-digit area pin code to see shops near you.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: pinController,
                keyboardType: const TextInputType.numberWithOptions(),
                maxLength: 6,
                                decoration: const InputDecoration(
                  hintText: 'e.g. 560001',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final pin = pinController.text.trim();
              if (pin.length == 6) {
                Navigator.of(dialogContext).pop();
                context.push('/search-results-by-pin/$pin');
              } else {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a valid 6-digit pin code'),
                  ),
                );
              }
            },
            child: const Text('Check'),
          ),
        ],
      ),
    );
  }
}
