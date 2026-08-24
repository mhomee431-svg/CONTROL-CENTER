import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../env/env_config.dart';
import '../theme/app_theme.dart';

/// Abstraction layer for Map Providers (Google Maps, Mapbox, OSM, etc.)
///
/// To swap providers later, create a new adapter class that implements
/// [MapAdapter] and change the [mapAdapterProvider] override. The rest
/// of the app remains untouched — true dependency inversion.
abstract class MapAdapter {
  Widget buildMap({
    required double userLat,
    required double userLng,
    required double destLat,
    required double destLng,
    required String destName,
  });

  /// Builds a loading placeholder while the map is initializing.
  Widget buildLoading();

  /// Builds an error placeholder when the map fails to load.
  Widget buildError({required String message, VoidCallback? onRetry});
}

// In a real app, this would return GoogleMapAdapter or MapboxAdapter.
final mapAdapterProvider = Provider<MapAdapter>((ref) => StubMapAdapter());

/// A visual placeholder that proves the abstraction works without
/// bloating the code with GoogleMaps dependencies.
///
/// Once a real provider is wired (Google Maps / Mapbox / OSM), replace
/// the [mapAdapterProvider] implementation with the real adapter.
class StubMapAdapter implements MapAdapter {
  @override
  Widget buildMap({
    required double userLat,
    required double userLng,
    required double destLat,
    required double destLng,
    required String destName,
  }) {
    return Container(
      color: Colors.grey.shade300,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Center(
            child: Text(
              'Interactive Map Provider\n(Abstracted via MapAdapter)',
              textAlign: TextAlign.center,
            ),
          ),
          const Positioned(
            top: 20,
            left: 20,
            child: Icon(Icons.person_pin_circle, color: Colors.blue, size: 40),
          ),
          const Positioned(
            bottom: 40,
            right: 40,
            child: Icon(Icons.location_on, color: Colors.red, size: 40),
          ),
          // Show API key presence (empty = not configured)
          if (EnvConfig.mapsApiKey.isEmpty)
            const Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Text(
                'Map provider not configured.\nRun with --dart-define=MAPS_API_KEY=...',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: Colors.black54),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget buildLoading() {
    return Container(
      color: Colors.grey.shade200,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator.adaptive(),
            SizedBox(height: 16),
            Text('Loading map...'),
          ],
        ),
      ),
    );
  }

  @override
  Widget buildError({required String message, VoidCallback? onRetry}) {
    return Container(
      color: Colors.grey.shade200,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.map_outlined, size: 48, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}
