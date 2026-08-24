import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../location/presentation/controllers/location_controller.dart';
import '../../../../core/theme/app_theme.dart';

class LocationHeader extends ConsumerWidget {
  const LocationHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationState = ref.watch(locationControllerProvider);
    final String city = locationState.location?.displayLabel ?? 'Select Location';
    final String address = locationState.location?.displayAddress ?? 'Tap to set address';

    return GestureDetector(
      onTap: () => context.push('/select-location'),
      child: Row(
        children: [
          // Current-location indicator
          const Icon(Icons.my_location, color: AppColors.primary, size: 28),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      city,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const Icon(Icons.keyboard_arrow_down, size: 20),
                  ],
                ),
                Text(
                  address,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Refresh button (only when a location is already set)
          if (locationState.status == LocationStatus.success)
            IconButton(
              icon: const Icon(Icons.refresh, size: 20, color: AppColors.textMuted),
              tooltip: 'Refresh location',
              onPressed: () =>
                  ref.read(locationControllerProvider.notifier).refreshLocation(),
            ),
        ],
      ),
    );
  }
}