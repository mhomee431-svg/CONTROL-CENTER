import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Locks the map-SDK boundary.
///
/// ## Why this matters
/// -----------------
/// `google_maps_flutter` types (`GoogleMap`, `CameraPosition`, `LatLng`,
/// `Marker`, `GoogleMapController`) are not interchangeable with any other map
/// provider. One `import` in a feature screen is how a "we might switch to
/// Mapbox" decision quietly becomes impossible: the screen compiles against
/// SDK types, so swapping the adapter leaves that screen broken.
///
/// The architecture already prevents this — `MapAdapter` builds the map widget
/// and `mapAdapterProvider` decides which implementation runs, which is why
/// `StubMapAdapter` can prove the whole thing works with no API key and no SDK.
/// What it cannot prevent is new code sidestepping it.
///
/// ## The known exception
/// ---------------------
/// `map_picker_screen.dart` is a full-screen interactive picker: camera
/// callbacks, a fixed centre pin, a polyline, and "recentre on me". None of that
/// fits `MapAdapter.buildMap`, which takes a destination and renders a finished
/// map. It therefore builds `GoogleMap` directly — a real gap, listed here
/// rather than hidden. Closing it means adding a picker entry point to
/// [MapAdapter] and routing the screen through it; the assertion below is
/// written to FAIL when that file stops importing the SDK, which is the prompt
/// to delete its line from this list.
void main() {
  /// Files permitted to import the map SDK. Keep this list as short as the
  /// architecture allows — every entry is a place a provider swap would break.
  const allowedSdkImporters = <String, String>{
    'google_map_adapter.dart':
        'The adapter itself. Constructing the SDK widget is precisely this '
        "file's job, and hiding it elsewhere would defeat the abstraction.",
    'map_picker_screen.dart':
        'OPEN GAP: a full-screen interactive picker (camera callbacks, fixed '
        'centre pin, polyline, recentre) that MapAdapter.buildMap does not '
        'model. Migrate once MapAdapter grows a picker entry point.',
  };

  /// Provider keys are owned by the adapter and must not leak either: a caller
  /// passing `initialCameraPosition` is holding an SDK type.
  final sdkTypes = <String>[
    'GoogleMap(',
    'GoogleMapController',
    'CameraPosition',
    'CameraUpdate',
    'LatLng(',
    'Marker(',
    'Polyline(',
    'GoogleMapId',
  ];

  group('the map SDK does not leak past the adapter', () {
    test('only permitted files import google_maps_flutter', () {
      final offenders = <String>[];

      for (final file in Directory('lib').listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final source = file.readAsStringSync();
        if (!source.contains('package:google_maps_flutter/')) continue;

        final name = file.path.split(RegExp(r'[/\\]')).last;
        if (allowedSdkImporters.containsKey(name)) continue;
        offenders.add(name);
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'these files import the map SDK directly. Build the map through '
            'MapAdapter instead so the provider stays swappable:\n'
            '${offenders.join('\n')}',
      );
    });

    test('the allowed set is not quietly growing', () {
      // A stale allowlist entry is worse than none: it reads as permission and
      // nobody remembers why it was granted.
      for (final entry in allowedSdkImporters.entries) {
        final hit = Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith(entry.key));
        expect(
          hit.isNotEmpty,
          isTrue,
          reason:
              '${entry.key} is allowlisted but no longer exists — remove it',
        );
        expect(
          File(hit.first.path).readAsStringSync(),
          contains('package:google_maps_flutter/'),
          reason:
              '${entry.key} is allowlisted for the SDK import but does not '
              'import it any more — remove it from the list',
        );
      }
    });

    test('the adapter interface itself stays SDK-free', () {
      // The whole design rests on this: if `MapAdapter` mentions SDK types, the
      // abstraction has already leaked and no amount of discipline downstream
      // will recover it.
      final adapter = File('lib/core/maps/map_adapter.dart').readAsStringSync();
      expect(
        adapter.contains('package:google_maps_flutter/'),
        isFalse,
        reason: 'MapAdapter is the seam — it must not import the SDK',
      );
      for (final type in sdkTypes) {
        expect(
          adapter.contains(type),
          isFalse,
          reason: 'MapAdapter must not name the SDK type "$type"',
        );
      }
    });

    test('the provider is chosen in one place', () {
      final adapter = File('lib/core/maps/map_adapter.dart').readAsStringSync();
      expect(
        adapter,
        contains('mapAdapterProvider'),
        reason:
            'swapping providers must be a single override, not a per-screen '
            'branch',
      );
      expect(
        adapter,
        contains('StubMapAdapter'),
        reason:
            'an unconfigured build must degrade to the stub rather than '
            'crash on a missing API key',
      );
    });
  });
}
