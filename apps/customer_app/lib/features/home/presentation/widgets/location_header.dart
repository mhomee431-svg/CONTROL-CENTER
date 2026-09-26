import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../location/presentation/controllers/location_controller.dart';
import '../../../../core/theme/app_theme.dart';

/// Zepto-style location header shown on the Home top bar.
///
/// Tapping opens the full-screen location picker. Shows the detected area
/// / sublocality prominently with the city + pincode underneath, and a
/// refresh spinner while a GPS fix is in flight.
class LocationHeader extends ConsumerWidget {
  const LocationHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationState = ref.watch(locationControllerProvider);
    final location = locationState.location;

    // Zepto-style: area / sublocality as the headline.
    final String headline = location?.address.isNotEmpty == true
        ? location!.address
        : (location?.displayLabel ?? 'Select Location');

    // Subtitle: city + pincode.
    final List<String> subtitleParts = [
      if (location?.city.isNotEmpty == true) location!.city,
      if (location?.pincode.isNotEmpty == true) location!.pincode,
    ];
    final String subtitle = subtitleParts.isEmpty
        ? (location == null ? 'Tap to set address' : 'Detecting...')
        : subtitleParts.join(' • ');

    final bool isLoading = locationState.status == LocationStatus.loading;

    return Row(
      children: [
        // Location takes the remaining width; the profile entry is fixed-size.
        Expanded(
          child: GestureDetector(
            onTap: () => context.push('/select-location'),
            child: Row(
              children: [
                // Current-location indicator (spinner while loading)
                if (isLoading)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                  )
                else
                  const Icon(
                    Icons.my_location,
                    color: AppColors.primary,
                    size: 28,
                  ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              headline,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.keyboard_arrow_down, size: 20),
                        ],
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Refresh button (only when a location is already set)
                if (locationState.status == LocationStatus.success)
                  IconButton(
                    icon: const Icon(
                      Icons.refresh,
                      size: 20,
                      color: AppColors.textMuted,
                    ),
                    tooltip: 'Refresh location',
                    onPressed: () => ref
                        .read(locationControllerProvider.notifier)
                        .refreshLocation(),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        // Header profile entry (the shell also has a Profile tab; this is the
        // always-reachable shortcut beside the location).
        IconButton(
          key: const Key('homeProfileButton'),
          icon: const Icon(Icons.account_circle_outlined),
          color: AppColors.textMuted,
          tooltip: 'Profile',
          onPressed: () => context.go('/profile'),
        ),
      ],
    );
  }
}
