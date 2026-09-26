import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/directions_controller.dart';
import '../../../../core/maps/map_adapter.dart';
import '../../domain/models/location_models.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/widgets/auth_gate_sheet.dart';

class DirectionsScreen extends ConsumerWidget {
  final String shopId;
  final String shopName;

  const DirectionsScreen({
    super.key,
    required this.shopId,
    this.shopName = 'Shop Destination',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(directionsControllerProvider(shopId));
    final controller = ref.read(directionsControllerProvider(shopId).notifier);
    final mapAdapter = ref.read(mapAdapterProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Route to Shop')),
      body: _buildBody(context, ref, state, controller, mapAdapter),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    DirectionsState state,
    DirectionsController controller,
    MapAdapter mapAdapter,
  ) {
    if (state.isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator.adaptive(),
            SizedBox(height: 16),
            Text('Acquiring GPS location...'),
          ],
        ),
      );
    }

    if (state.error != null) {
      return _buildErrorState(state.error!, controller);
    }

    if (state.userLocation == null || state.shopLocation == null) {
      return const Center(child: Text('Map loading error.'));
    }

    return Column(
      children: [
        // Map Abstraction View
        Expanded(
          child: mapAdapter.buildMap(
            userLat: state.userLocation!.latitude,
            userLng: state.userLocation!.longitude,
            destLat: state.shopLocation!.latitude,
            destLng: state.shopLocation!.longitude,
            destName: shopName,
          ),
        ),

        // Bottom Information Sheet
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 10,
                offset: Offset(0, -5),
              ),
            ],
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (state.isShopClosed) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 18,
                          color: AppColors.error,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'This shop is currently closed. You can still navigate to it.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Destination',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          shopName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${state.distanceInKm} km',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final allowed = await requireAuthentication(
                        context,
                        ref,
                        actionLabel: 'start navigation',
                      );
                      if (!allowed || !context.mounted) return;
                      await controller.launchExternalMaps(shopName);
                    },
                    icon: const Icon(Icons.navigation),
                    label: const Text('Open External Navigation'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(
    LocationErrorType error,
    DirectionsController controller,
  ) {
    IconData icon;
    String title;
    String message;
    String buttonText = 'Retry';

    switch (error) {
      case LocationErrorType.noGps:
        icon = Icons.gps_off;
        title = 'GPS Disabled';
        message = 'Please turn on your location services to get directions.';
        buttonText = 'Open Settings';
        break;
      case LocationErrorType.permissionDenied:
        icon = Icons.location_off;
        title = 'Permission Denied';
        message = 'We need location access to show you the route to the shop.';
        buttonText = 'Allow Location';
        break;
      case LocationErrorType.permissionPermanentlyDenied:
        icon = Icons.location_disabled;
        title = 'Permission Blocked';
        message = 'Location permission is permanently blocked. Please enable it in system settings.';
        buttonText = 'Open Settings';
        break;
      case LocationErrorType.invalidCoordinates:
        icon = Icons.wrong_location;
        title = 'Invalid Location';
        message = 'The shop location appears to be invalid or missing.';
        break;
      case LocationErrorType.networkFailure:
        icon = Icons.error_outline;
        title = 'Network or Map Error';
        message = 'Something went wrong while loading the map.';
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
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              onPressed: () => controller.retry(),
              child: Text(buttonText),
            ),
          ],
        ),
      ),
    );
  }
}
