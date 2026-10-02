import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../env/env_config.dart';
import '../theme/app_theme.dart';
import 'google_map_adapter.dart';

/// Shared failure panel for every map provider.
///
/// Lives in the platform-agnostic layer so the Google Maps SDK, the
/// deterministic stub, and any future provider (Mapbox/OSM) all render the
/// same "map unavailable" state instead of a blank grey tile. [onRetry] is
/// optional: omit it when there is nothing meaningful to retry.
class MapErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const MapErrorView({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted),
              ),
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

/// A lightweight description of a shop cluster on a dense multi-shop map.
///
/// Produced by [clusterMarkers] so the UI, search results, and tests share the
/// same rule: a cluster is a *count shown at one position*, never a fake shop.
class MapClusterInfo {
  final double latitude;
  final double longitude;
  final int count;
  final List<MapMarkerInfo> members;

  const MapClusterInfo({
    required this.latitude,
    required this.longitude,
    required this.count,
    required this.members,
  });
}

/// Groups nearby markers into clusters when the marker count exceeds
/// [clusterThreshold] (default 12).
///
/// The grid is intentionally coarse: latitude/longitude are rounded to
/// [cellSizeDegrees] (default ~1.1 km at the equator) and every marker in the
/// same cell becomes one cluster positioned at the members' centroid. When the
/// count is at/below the threshold the input list is returned untouched, so
/// normal maps render every shop marker individually.
///
/// Pass [maxMarkers] to bound the result regardless of clustering, together
/// with [originLatitude]/[originLongitude] so the cap keeps the nearest
/// entries. See [_capMarkers] for why the cap exists at all.
List<Object> clusterMarkers(
  List<MapMarkerInfo> shops, {
  int clusterThreshold = 12,
  double cellSizeDegrees = 0.01,
  int? maxMarkers,
  double? originLatitude,
  double? originLongitude,
}) {
  if (shops.length <= clusterThreshold) {
    return _capMarkers(
      List<Object>.of(shops),
      maxMarkers: maxMarkers,
      originLatitude: originLatitude,
      originLongitude: originLongitude,
    );
  }
  final cells = <String, List<MapMarkerInfo>>{};
  for (final shop in shops) {
    final key =
        '${(shop.latitude / cellSizeDegrees).floor()}:'
        '${(shop.longitude / cellSizeDegrees).floor()}';
    (cells[key] ??= <MapMarkerInfo>[]).add(shop);
  }
  final clustered = cells.values.map((members) {
    if (members.length == 1) return members.first;
    var lat = 0.0;
    var lng = 0.0;
    for (final member in members) {
      lat += member.latitude;
      lng += member.longitude;
    }
    return MapClusterInfo(
      latitude: lat / members.length,
      longitude: lng / members.length,
      count: members.length,
      members: List<MapMarkerInfo>.unmodifiable(members),
    );
  }).toList();
  return _capMarkers(
    clustered,
    maxMarkers: maxMarkers,
    originLatitude: originLatitude,
    originLongitude: originLongitude,
  );
}

/// Great-circle distance between two coordinates, in metres.
///
/// Exposed (and pure) so the marker cap can order by "nearest to the customer"
/// without a device, and so tests can assert the ordering directly.
double haversineMeters({
  required double fromLat,
  required double fromLng,
  required double toLat,
  required double toLng,
}) {
  const earthRadiusMeters = 6371000.0;
  double toRadians(double degrees) => degrees * math.pi / 180.0;
  final dLat = toRadians(toLat - fromLat);
  final dLng = toRadians(toLng - fromLng);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(toRadians(fromLat)) *
          math.cos(toRadians(toLat)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return 2 * earthRadiusMeters * math.asin(math.min(1.0, math.sqrt(a)));
}

/// Truncates [entries] to [maxMarkers], keeping the ones closest to the origin.
///
/// WHY A CAP IS NEEDED EVEN AFTER CLUSTERING
/// ---------------------------------------
/// Clustering only collapses markers that share a grid cell. A search returning
/// 40 shops spread over a city produces 40 markers and 40 InfoWindows, because
/// no two of them ever land in the same cell. Every one of those is a platform
/// view, an icon bitmap, and an InfoWindow to allocate on each rebuild, so the
/// map gets steadily more expensive exactly as the customer pans toward the
/// dense area they care about.
///
/// The nearest ones are kept because a customer scanning "dove shampoo" wants
/// the shops they can actually walk to; a marker 30 km away is not a useful
/// pin. Ties fall back to the incoming order so the result is deterministic
/// (Dart's [List.sort] is not stable, so the index is an explicit tiebreak).
///
/// With no [maxMarkers] (the default) the input is returned untouched, which is
/// what the plain cluster behaviour and its existing callers/tests expect.
List<Object> _capMarkers(
  List<Object> entries, {
  required int? maxMarkers,
  required double? originLatitude,
  required double? originLongitude,
}) {
  if (maxMarkers == null || entries.length <= maxMarkers) return entries;
  final bounded = maxMarkers < 0 ? 0 : maxMarkers;
  if (bounded == 0) return const <Object>[];

  final hasOrigin = originLatitude != null && originLongitude != null;
  if (!hasOrigin) return entries.sublist(0, bounded);

  final indexed = <({int index, Object entry, double distance})>[];
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final latitude = switch (entry) {
      MapMarkerInfo marker => marker.latitude,
      MapClusterInfo cluster => cluster.latitude,
      _ => null,
    };
    final longitude = switch (entry) {
      MapMarkerInfo marker => marker.longitude,
      MapClusterInfo cluster => cluster.longitude,
      _ => null,
    };
    if (latitude == null || longitude == null) continue;
    indexed.add((
      index: i,
      entry: entry,
      distance: haversineMeters(
        fromLat: originLatitude,
        fromLng: originLongitude,
        toLat: latitude,
        toLng: longitude,
      ),
    ));
  }
  // An unrecognised entry type means the caller handed us something this
  // function cannot order by distance. Dropping those silently would hide
  // shops, so keep the original order rather than guessing.
  if (indexed.length != entries.length) return entries.sublist(0, bounded);

  indexed.sort((a, b) {
    final byDistance = a.distance.compareTo(b.distance);
    return byDistance != 0 ? byDistance : a.index.compareTo(b.index);
  });
  return <Object>[for (var i = 0; i < bounded; i++) indexed[i].entry];
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
