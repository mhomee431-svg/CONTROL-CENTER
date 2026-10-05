import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/maps/google_map_adapter.dart';
import 'package:hyperlocal_app/core/maps/map_adapter.dart';

MapMarkerInfo _shop(String name, double lat, double lng) =>
    MapMarkerInfo(latitude: lat, longitude: lng, label: name);

void main() {
  group('haversineMeters', () {
    test('is zero for the same point', () {
      expect(
        haversineMeters(fromLat: 25.6, fromLng: 85.1, toLat: 25.6, toLng: 85.1),
        closeTo(0, 0.001),
      );
    });

    test('measures one degree of latitude as roughly 111 km', () {
      expect(
        haversineMeters(fromLat: 0, fromLng: 0, toLat: 1, toLng: 0),
        closeTo(111195, 500),
      );
    });

    test('is symmetric', () {
      final forward = haversineMeters(
        fromLat: 25.5941,
        fromLng: 85.1376,
        toLat: 25.6,
        toLng: 85.2,
      );
      final backward = haversineMeters(
        fromLat: 25.6,
        fromLng: 85.2,
        toLat: 25.5941,
        toLng: 85.1376,
      );
      expect(forward, closeTo(backward, 0.001));
    });
  });

  group('clusterMarkers marker cap', () {
    test('returns every marker untouched when no cap is given', () {
      final shops = List.generate(
        40,
        (i) => _shop('S$i', 25.0 + i * 0.5, 85.0),
      );
      expect(clusterMarkers(shops).length, 40);
    });

    test('caps markers that clustering could not collapse', () {
      // Each shop sits in its own grid cell (0.5 degrees apart), so clustering
      // leaves all 40 as individual markers. This is the real hazard: 40
      // platform views, 40 icon bitmaps and 40 InfoWindows for one search.
      final shops = List.generate(
        40,
        (i) => _shop('S$i', 25.0 + i * 0.5, 85.0),
      );
      final clustered = clusterMarkers(
        shops,
        maxMarkers: 10,
        originLatitude: 25.0,
        originLongitude: 85.0,
      );
      expect(clustered.length, 10);
    });

    test('keeps the nearest markers, not the first ones', () {
      // S0 is nearest and S39 furthest, so a naive head-truncation would keep
      // the ten most distant shops on the map.
      final shops = List.generate(
        40,
        (i) => _shop('S$i', 25.0 + i * 0.5, 85.0),
      );
      final clustered = clusterMarkers(
        shops,
        maxMarkers: 10,
        originLatitude: 25.0,
        originLongitude: 85.0,
      );
      final labels = clustered.map((e) => (e as MapMarkerInfo).label).toList();
      expect(labels.first, 'S0');
      expect(labels.last, 'S9');
      expect(labels, isNot(contains('S39')));
    });

    test('a cap of zero yields no markers rather than throwing', () {
      final shops = List.generate(5, (i) => _shop('S$i', 25.0 + i, 85.0));
      expect(
        clusterMarkers(
          shops,
          maxMarkers: 0,
          originLatitude: 25.0,
          originLongitude: 85.0,
        ),
        isEmpty,
      );
    });

    test('a cap above the marker count changes nothing', () {
      final shops = List.generate(5, (i) => _shop('S$i', 25.0 + i, 85.0));
      expect(
        clusterMarkers(
          shops,
          maxMarkers: 50,
          originLatitude: 25.0,
          originLongitude: 85.0,
        ).length,
        5,
      );
    });

    test('without an origin the cap keeps the incoming order', () {
      final shops = List.generate(20, (i) => _shop('S$i', 25.0 + i, 85.0));
      final capped = clusterMarkers(shops, maxMarkers: 3);
      expect(capped.map((e) => (e as MapMarkerInfo).label).toList(), [
        'S0',
        'S1',
        'S2',
      ]);
    });
  });

  group('MapMarkerIcons', () {
    setUp(MapMarkerIcons.resetForTesting);

    test('returns the identical descriptor for every marker of a hue', () {
      // The whole point of the cache: one hue must not rebuild a platform-side
      // bitmap descriptor for each marker.
      expect(identical(MapMarkerIcons.rose, MapMarkerIcons.rose), isTrue);
    });

    test('different hues are different descriptors', () {
      expect(identical(MapMarkerIcons.azure, MapMarkerIcons.rose), isFalse);
      expect(identical(MapMarkerIcons.rose, MapMarkerIcons.orange), isFalse);
    });
  });

  group('GoogleMapScene.forShops', () {
    test('never renders more markers than the cap plus the user pin', () {
      final shops = List.generate(
        200,
        (i) => _shop('S$i', 25.0 + i * 0.01, 85.0 + i * 0.01),
      );
      final scene = GoogleMapScene.forShops(
        userLat: 25.0,
        userLng: 85.0,
        shops: shops,
      );
      // +1 is the "your location" pin, added outside the cap.
      expect(
        scene.markers.length,
        lessThanOrEqualTo(kMaxRenderedShopMarkers + 1),
      );
      expect(scene.markers.length, greaterThan(1));
    });

    test('shares one shop marker icon across all shop markers', () {
      final shops = List.generate(
        30,
        (i) => _shop('S$i', 25.0 + i * 0.01, 85.0),
      );
      final scene = GoogleMapScene.forShops(
        userLat: 25.0,
        userLng: 85.0,
        shops: shops,
      );
      // user (azure) + shop (rose) = 2 distinct descriptors, not 31.
      expect(scene.markers.map((m) => m.icon).toSet().length, 2);
    });

    test('a short list still renders one marker per shop', () {
      final scene = GoogleMapScene.forShops(
        userLat: 25.0,
        userLng: 85.0,
        shops: [
          _shop('A', 25.01, 85.01),
          _shop('B', 25.02, 85.02),
          _shop('C', 25.03, 85.03),
        ],
      );
      expect(scene.markers.length, 4); // 3 shops + the user pin
    });
  });
}
