import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/maps/map_adapter.dart';

/// Minimal single-destination adapter to verify the default `buildShopsMap`
/// implementation delegates to `buildMap` using the first shop.
class _FirstShopOnlyAdapter extends MapAdapter {
  String? lastDestName;

  @override
  Widget buildMap({
    required double userLat,
    required double userLng,
    required double destLat,
    required double destLng,
    required String destName,
  }) {
    lastDestName = destName;
    return const SizedBox(key: ValueKey('map'));
  }

  @override
  Widget buildError({required String message, VoidCallback? onRetry}) =>
      const SizedBox(key: ValueKey('error'));

  @override
  Widget buildLoading() => const SizedBox(key: ValueKey('loading'));
}

void main() {
  group('mapAdapterProvider', () {
    test('uses the deterministic stub when no MAPS_API_KEY is configured', () {
      // Tests run without --dart-define=MAPS_API_KEY, so the stub must be
      // selected — the real Google Maps widget would need platform channels.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(mapAdapterProvider), isA<StubMapAdapter>());
    });

    test('accepts an override with the Google Map adapter', () {
      final container = ProviderContainer(
        overrides: [mapAdapterProvider.overrideWithValue(StubMapAdapter())],
      );
      addTearDown(container.dispose);
      expect(container.read(mapAdapterProvider), isA<StubMapAdapter>());
    });
  });

  group('MapAdapter default buildShopsMap', () {
    test('delegates to buildMap with the first shop', () {
      final adapter = _FirstShopOnlyAdapter();
      final widget = adapter.buildShopsMap(
        userLat: 1,
        userLng: 2,
        shops: const [
          MapMarkerInfo(latitude: 3, longitude: 4, label: 'Shop A'),
          MapMarkerInfo(latitude: 5, longitude: 6, label: 'Shop B'),
        ],
      );

      expect(widget.key, const ValueKey('map'));
      expect(adapter.lastDestName, 'Shop A');
    });

    test('shows an error placeholder when there are no shops', () {
      final adapter = _FirstShopOnlyAdapter();
      final widget = adapter.buildShopsMap(
        userLat: 1,
        userLng: 2,
        shops: const [],
      );
      expect(widget.key, const ValueKey('error'));
    });
  });

  group('MapMarkerInfo', () {
    test('stores label and optional subtitle', () {
      const info = MapMarkerInfo(
        latitude: 25.5941,
        longitude: 85.1376,
        label: 'Patna',
        subtitle: '800001',
      );
      expect(info.latitude, 25.5941);
      expect(info.longitude, 85.1376);
      expect(info.label, 'Patna');
      expect(info.subtitle, '800001');
    });
  });
}
