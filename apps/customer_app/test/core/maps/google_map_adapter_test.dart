import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_customer_app/core/maps/google_map_adapter.dart';
import 'package:hyperlocal_customer_app/core/maps/map_adapter.dart';

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
  });
}
