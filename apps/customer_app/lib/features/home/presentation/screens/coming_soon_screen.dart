import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../location/presentation/controllers/location_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../controllers/home_radius_controller.dart';
import '../widgets/no_nearby_shops_actions.dart';

/// Standalone "no shops in your area" screen, reachable directly at
/// `/coming-soon` (deep link / splash fallback).
///
/// It used to hand-roll its own recovery list — a pin-code button and a
/// location retry — which meant this route offered two recoveries while the
/// in-feed empty state offered three. It now renders the SAME
/// [NoNearbyShopsActions] widget, so a customer who lands here directly is not
/// given a strictly worse set of ways out than one who reaches the empty state
/// from the home feed.
class ComingSoonScreen extends ConsumerWidget {
  const ComingSoonScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(locationControllerProvider).location;
    // The VALUE, not the notifier: watching `p.notifier` returns a stable
    // object, so a radius change would never repaint this screen and the label
    // would keep advertising a step it can no longer take.
    final radiusKm = ref.watch(homeSearchRadiusProvider);

    // NOTE: intentionally NO Scaffold here, and only ONE scroll view. The
    // shared `NoNearbyShopsActions` widget brings its own
    // `Center` + `SingleChildScrollView`, so this screen uses the
    // `buildNoNearbyShopsActions` DATA half and lays the buttons out inside its
    // own scroll view instead — nesting a second unbounded scroll view here
    // would throw "RenderViewport was given an infinite size".
    // The /coming-soon route wraps this widget in its own Scaffold.
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          const Icon(Icons.rocket_launch, size: 90, color: AppColors.primary),
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
            'Below are the ways to keep looking right now.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted, height: 1.4),
            textAlign: TextAlign.center,
          ),
          if (location != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'Detected location: ${location.displayAddress}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.primary),
              textAlign: TextAlign.center,
            ),
          ],
          // Identical recoveries to the in-feed empty state, including the
          // radius ladder — the DATA half only, so the buttons sit inside THIS
          // screen's single scroll view. Widening re-reads the home feed,
          // because this screen shares `homeSearchRadiusProvider` with it.
          for (final action in buildNoNearbyShopsActions(
            context: context,
            radiusKm: radiusKm,
            keyPrefix: 'comingSoon',
            onWidenRadius: () =>
                ref.read(homeSearchRadiusProvider.notifier).widen(),
          ))
            OutlinedButton.icon(
              key: action.key,
              onPressed: action.onTap,
              icon: Icon(action.icon, size: 18),
              label: Text(action.label),
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
}
