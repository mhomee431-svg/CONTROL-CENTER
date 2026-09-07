import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../env/env_config.dart';
import '../theme/app_theme.dart';
import 'google_map_adapter.dart';

/// A lightweight marker description for the multi-shop map.
///
/// Kept in the platform-agnostic layer so search results, home, and other
/// features can describe markers without importing the Google Maps SDK.
class MapMarkerInfo {
  final double latitude;
  final double longitude;
  final String label;
  final String? subtitle;

  const MapMarkerInfo({
    required this.latitude,
    required this.longitude,
    required this.label,
    this.subtitle,
  });
}

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

  /// Multi-marker map for a list of shops.
  ///
  /// The default implementation renders the first shop through the
  /// single-destination [buildMap], so single-marker adapters keep working
  /// without implementing this method.
  Widget buildShopsMap({
    required double userLat,
    required double userLng,
    required List<MapMarkerInfo> shops,
  }) {
    if (shops.isEmpty) {
      return buildError(message: 'No shop locations to display');
    }
    final first = shops.first;
    return buildMap(
      userLat: userLat,
      userLng: userLng,
      destLat: first.latitude,
      destLng: first.longitude,
      destName: first.label,
    );
  }

  /// Builds a loading placeholder while the map is initializing.
  Widget buildLoading();

  /// Builds an error placeholder when the map fails to load.
  Widget buildError({required String message, VoidCallback? onRetry});
}

// A configured `MAPS_API_KEY` (compile-time dart-define) enables the real
// Google Maps SDK; otherwise the deterministic stub keeps debug/test builds
// (and unconfigured builds) from crashing with a blank map.
final mapAdapterProvider = Provider<MapAdapter>((ref) {
  return EnvConfig.mapsApiKey.isNotEmpty
      ? const GoogleMapAdapter()
      : StubMapAdapter();
});

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
  Widget buildShopsMap({
    required double userLat,
    required double userLng,
    required List<MapMarkerInfo> shops,
  }) {
    return Container(
      color: Colors.grey.shade300,
      child: Stack(
        children: [
          const Center(
            child: Text(
              'Interactive Map Provider\n(Abstracted via MapAdapter)',
              textAlign: TextAlign.center,
            ),
          ),
          Positioned(
            top: 20,
            left: 20,
            child: Row(
              children: [
                const Icon(
                  Icons.person_pin_circle,
                  color: Colors.blue,
                  size: 40,
                ),
                const SizedBox(width: 8),
                Text(
                  '${shops.length} shops',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          for (var i = 0; i < shops.length.clamp(0, 6); i++)
            Positioned(
              left: 40.0 + (i % 3) * 70,
              bottom: 40.0 + (i ~/ 3) * 55,
              child: const Icon(Icons.location_on, color: Colors.red, size: 40),
            ),
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
            const Icon(
              Icons.map_outlined,
              size: 48,
              color: AppColors.textMuted,
            ),
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
