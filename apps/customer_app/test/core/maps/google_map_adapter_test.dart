import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/maps/google_map_adapter.dart';
import 'package:hyperlocal_app/core/maps/map_adapter.dart';

void main() {
  group('GoogleMapScene.forRoute', () {
    final scene = GoogleMapScene.forRoute(
      userLat: 25.5941,
      userLng: 85.1376,
      destLat: 25.6100,
      destLng: 85.1500,
      destName: 'Corner Store',
    );

    test('creates a user marker and a destination marker', () {
      final markers = scene.markers.toList();
      expect(markers, hasLength(2));

      final user = markers.firstWhere(
        (m) => m.markerId.value == 'user_location',
      );
      expect(user.position.latitude, closeTo(25.5941, 1e-6));
      expect(user.position.longitude, closeTo(85.1376, 1e-6));

      final dest = markers.firstWhere((m) => m.markerId.value == 'destination');
      expect(dest.position.latitude, closeTo(25.6100, 1e-6));
      expect(dest.position.longitude, closeTo(85.1500, 1e-6));
      expect(dest.infoWindow.title, 'Corner Store');
    });

    test('draws a directions polyline connecting user and shop', () {
      expect(scene.polylines, hasLength(1));
      final poly = scene.polylines.first;
      expect(poly.polylineId.value, 'directions_route');
      expect(poly.points, hasLength(2));
      expect(poly.points.first.latitude, closeTo(25.5941, 1e-6));
      expect(poly.points.last.longitude, closeTo(85.1500, 1e-6));
    });

    test('camera is centered between both points and bounds contain them', () {
      final bounds = scene.bounds;
      expect(bounds, isNotNull);
      expect(
        bounds!.southwest.latitude <= 25.5941 &&
            bounds.northeast.latitude >= 25.61,
        isTrue,
      );
      expect(
        bounds.southwest.longitude <= 85.1376 &&
            bounds.northeast.longitude >= 85.15,
        isTrue,
      );
      final target = scene.initialCamera.target;
      expect(target.latitude, inInclusiveRange(25.5941, 25.61));
      expect(target.longitude, inInclusiveRange(85.1376, 85.15));
    });
  });

  group('clusterMarkers', () {
    MapMarkerInfo shop(int i) =>
        MapMarkerInfo(latitude: 28.7150, longitude: 77.1150, label: 'Shop $i');

    test('returns every marker untouched at or below the threshold', () {
      final shops = List.generate(12, shop);
      final result = clusterMarkers(shops);
      expect(result, hasLength(12));
      expect(result.whereType<MapMarkerInfo>(), hasLength(12));
      expect(result.whereType<MapClusterInfo>(), isEmpty);
    });

    test('groups dense markers into one cluster at their centroid', () {
      final shops = [
        const MapMarkerInfo(latitude: 28.7150, longitude: 77.1150, label: 'A'),
        const MapMarkerInfo(latitude: 28.7152, longitude: 77.1152, label: 'B'),
        const MapMarkerInfo(latitude: 28.7148, longitude: 77.1148, label: 'C'),
      ];
      // Force clustering regardless of count for this geometry check.
      final result = clusterMarkers(shops, clusterThreshold: 1);
      expect(result, hasLength(1));

      final cluster = result.single as MapClusterInfo;
      expect(cluster.count, 3);
      expect(cluster.members.map((m) => m.label), containsAll(['A', 'B', 'C']));
      // All three share a grid cell, so the centroid matches them.
      expect(cluster.latitude, closeTo(28.7150, 1e-6));
      expect(cluster.longitude, closeTo(77.1150, 1e-6));
    });

    test('keeps distant markers as separate individual pins', () {
      final shops = [
        const MapMarkerInfo(latitude: 28.7150, longitude: 77.1150, label: 'A'),
        const MapMarkerInfo(latitude: 28.8150, longitude: 77.1150, label: 'B'),
      ];
      final result = clusterMarkers(shops, clusterThreshold: 1);
      expect(result, hasLength(2));
      expect(result.whereType<MapMarkerInfo>(), hasLength(2));
      expect(result.whereType<MapClusterInfo>(), isEmpty);
    });

    test('preserves every shop across clusters (no marker is lost)', () {
      final shops = <MapMarkerInfo>[
        // 9 in one cell
        for (var i = 0; i < 9; i++)
          MapMarkerInfo(
            latitude: 28.7150 + i * 1e-4,
            longitude: 77.1150,
            label: 'A$i',
          ),
        // 4 in a far cell
        for (var i = 0; i < 4; i++)
          MapMarkerInfo(
            latitude: 28.8150 + i * 1e-4,
            longitude: 77.1150,
            label: 'B$i',
          ),
      ];
      final result = clusterMarkers(shops);
      final clustered = result.whereType<MapClusterInfo>();
      final individual = result.whereType<MapMarkerInfo>();

      final represented =
          clustered.expand((c) => c.members).length + individual.length;
      expect(represented, shops.length);
      // Both dense cells collapse to a single marker.
      expect(clustered, hasLength(2));
      expect(result, hasLength(2));
    });

    test('is a no-op for an empty list', () {
      expect(clusterMarkers(const []), isEmpty);
    });
  });

  group('GoogleMapScene.forShops', () {
    test('renders user + one marker per shop', () {
      final scene = GoogleMapScene.forShops(
        userLat: 25.5941,
        userLng: 85.1376,
        shops: const [
          MapMarkerInfo(
            latitude: 25.60,
            longitude: 85.14,
            label: 'Shop A',
            subtitle: '₹50',
          ),
          MapMarkerInfo(latitude: 25.61, longitude: 85.15, label: 'Shop B'),
        ],
      );

      expect(scene.markers, hasLength(3));
      expect(scene.markers.any((m) => m.markerId.value == 'shop_0'), isTrue);
      expect(scene.markers.any((m) => m.markerId.value == 'shop_1'), isTrue);
      expect(scene.polylines, isEmpty);
      expect(scene.bounds, isNotNull);
    });

    test('handles empty shops by centering on the user', () {
      final scene = GoogleMapScene.forShops(
        userLat: 25.5941,
        userLng: 85.1376,
        shops: const [],
      );
      expect(scene.markers, hasLength(1));
      expect(scene.markers.first.markerId.value, 'user_location');
    });

    test('dense shop lists render one count marker per cluster', () {
      final scene = GoogleMapScene.forShops(
        userLat: 28.7150,
        userLng: 77.1150,
        shops: [
          // 14 shops inside a single grid cell.
          for (var i = 0; i < 14; i++)
            MapMarkerInfo(
              latitude: 28.7150 + i * 1e-4,
              longitude: 77.1150,
              label: 'Shop $i',
            ),
        ],
      );

      // user + 1 cluster, not 14 overlapping pins.
      expect(scene.markers, hasLength(2));
      final cluster = scene.markers.firstWhere(
        (m) => m.markerId.value.startsWith('cluster_'),
      );
      expect(cluster.infoWindow.title, '14 shops');
      expect(cluster.infoWindow.snippet, contains('Shop 0'));
      // The cluster still counts as a real point for camera framing.
      expect(scene.bounds, isNotNull);
    });
  });

  group('Maps SDK error handling', () {
    test('API-key failures are reported as a configuration problem', () {
      expect(
        GoogleMapsViewState.isMapsKeyError(
          'The Google Maps Android API v3 requires a valid API key.',
        ),
        isTrue,
      );
      expect(
        GoogleMapsViewState.describeMapPlatformError('Invalid API key'),
        contains('API key'),
      );
    });

    test('other failures are reported as transient connection problems', () {
      expect(GoogleMapsViewState.isMapsKeyError('Network timeout'), isFalse);
      expect(
        GoogleMapsViewState.describeMapPlatformError('Network timeout'),
        contains('connection'),
      );
    });

    testWidgets('a reported failure replaces the map and Retry restores it', (
      tester,
    ) async {
      final state = GlobalKey<GoogleMapsViewState>();

      await tester.pumpWidget(
        MaterialApp(
          home: GoogleMapsView(
            key: state,
            scene: GoogleMapScene.forRoute(
              userLat: 25.5941,
              userLng: 85.1376,
              destLat: 25.6100,
              destLng: 85.1500,
              destName: 'Corner Store',
            ),
          ),
        ),
      );

      expect(find.byType(MapErrorView), findsNothing);
      expect(state.currentState!.platformError, isNull);

      state.currentState!.showError(
        GoogleMapsViewState.describeMapPlatformError('Invalid API key'),
      );
      await tester.pump();

      expect(find.byType(MapErrorView), findsOneWidget);
      expect(find.textContaining('API key'), findsOneWidget);
      expect(state.currentState!.platformError, isNotNull);

      // Retry clears the error and puts the real map back.
      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(find.byType(MapErrorView), findsNothing);
      expect(state.currentState!.platformError, isNull);
    });
  });

  group('MapErrorView', () {
    testWidgets('shows the message and hides Retry without a callback', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: MapErrorView(message: 'No map available')),
        ),
      );

      expect(find.text('No map available'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });
  });
}
