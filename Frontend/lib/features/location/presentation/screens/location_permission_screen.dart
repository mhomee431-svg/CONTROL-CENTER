import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../controllers/location_controller.dart';
import '../../domain/location_repository.dart';
import '../../../../core/theme/app_theme.dart';

class LocationPermissionScreen extends ConsumerWidget {
  const LocationPermissionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationState = ref.watch(locationControllerProvider);

    ref.listen<LocationState>(locationControllerProvider, (previous, next) {
      if (next.status == LocationStatus.success) {
        context.go('/'); // Navigate to Home on success
      } else if (next.status == LocationStatus.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.errorMessage ?? 'Error')),
        );
      } else if (next.status == LocationStatus.permissionDenied) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.errorMessage ?? 'Location permission denied')),
        );
      } else if (next.status == LocationStatus.permissionPermanentlyDenied) {
        _showPermanentlyDeniedDialog(context, ref);
      } else if (next.status == LocationStatus.serviceDisabled) {
        _showEnableLocationDialog(context, ref);
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_on, size: 80, color: AppColors.primary),
              const SizedBox(height: AppSpacing.lg),
              const Text(
                'Find Products Nearby',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'We need your location to show you which local shops currently have the products you are searching for.',
                style: TextStyle(fontSize: 16, color: AppColors.textMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: locationState.status == LocationStatus.loading
                      ? null
                      : () => ref
                          .read(locationControllerProvider.notifier)
                          .fetchCurrentLocation(),
                  child: locationState.status == LocationStatus.loading
                      ? const CircularProgressIndicator.adaptive()
                      : const Text('Allow Location Access'),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextButton(
                onPressed: () => context.push('/select-location'),
                child: const Text('Select Location Manually'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEnableLocationDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Location Services Disabled'),
        content: const Text(
          'GPS is turned off. Please enable location services to find nearby shops.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              ref
                  .read(locationRepositoryProvider)
                  .openLocationSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _showPermanentlyDeniedDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Location Permission Permanently Denied'),
        content: const Text(
          'You have permanently denied location access. '
          'Please enable location permission in your device settings to find nearby shops.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              ref
                  .read(locationRepositoryProvider)
                  .openLocationSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}