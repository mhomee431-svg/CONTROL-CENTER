import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Locks the "one location service" rule.
///
/// ## Why this needs enforcing rather than trusting
/// -----------------------------------------------
/// Location is the easiest thing in a mobile app to duplicate, because the
/// plugin call is one line: any screen can `import 'package:geolocator'` and
/// ask for a fix. The duplication is invisible in review — each copy looks
/// reasonable — and the costs only appear later:
///
///  * two screens prompting for permission means two explanations, or a
///    customer who granted it once being asked again with different wording;
///  * each copy invents its own timeout and accuracy threshold, so "near me"
///    means a different distance on different screens;
///  * permission state is re-derived per screen, so the UI can disagree with
///    itself after a revoke in system settings.
///
/// So this asserts the boundary: the plugin is reachable only from the data
/// layer, and everything else goes through the one service.
void main() {
  /// The only files permitted to touch the device-location plugin.
  ///
  /// Both are `data/` implementations behind [LocationService]. Everything
  /// else must go through the abstraction, which is what makes the provider
  /// swappable for tests and keeps permission wording in one place.
  const allowedPluginImporters = <String>{
    'device_location_service.dart',
    'device_location_repository.dart',
  };

  /// The only file permitted to talk to `permission_handler` directly.
  const allowedPermissionImporter = 'permission_service.dart';

  List<File> dartFiles() =>
      Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();

  String nameOf(File f) => f.path.split(RegExp(r'[/\\]')).last;

  group('only the data layer touches the device-location plugin', () {
    test('no screen or controller imports geolocator', () {
      final offenders = <String>[];

      for (final file in dartFiles()) {
        final source = file.readAsStringSync();
        if (!source.contains('package:geolocator')) continue;

        final name = nameOf(file);
        if (allowedPluginImporters.contains(name)) continue;

        // The real failure this prevents, spelled out in the message: a screen
        // that reads its own fix invents its own timeout and accuracy, so
        // "near me" quietly means something different on each screen.
        offenders.add(file.path.replaceAll(r'\', '/'));
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'these files read the device location directly. Use '
            'LocationService / locationControllerProvider instead, so timeout, '
            'accuracy and permission wording stay defined once:\n'
            '${offenders.join('\n')}',
      );
    });

    test('the allowed importers actually are in the data layer', () {
      // An allowlist that drifts toward presentation is worse than none: it
      // reads as permission and nobody remembers granting it.
      for (final name in allowedPluginImporters) {
        final hit = dartFiles().where((f) => nameOf(f) == name).toList();
        expect(
          hit,
          isNotEmpty,
          reason: '$name is allowlisted but no longer exists — remove it',
        );
        expect(
          hit.first.path.replaceAll(r'\', '/'),
          contains('/data/'),
          reason:
              '$name may only live in the data layer; it is currently at '
              '${hit.first.path}',
        );
      }
    });

    test('permission_handler is touched in exactly one place', () {
      final offenders = <String>[];
      for (final file in dartFiles()) {
        if (!file.readAsStringSync().contains('package:permission_handler')) {
          continue;
        }
        if (nameOf(file) == allowedPermissionImporter) continue;
        offenders.add(file.path.replaceAll(r'\', '/'));
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'permission prompts must come from one service so the customer '
            'is never asked twice, or asked twice in different words:\n'
            '${offenders.join('\n')}',
      );
    });
  });

  group('the service covers the responsibilities it is the owner of', () {
    String serviceSource() {
      final hit = dartFiles()
          .where((f) => nameOf(f) == 'location_service.dart')
          .toList();
      expect(hit, isNotEmpty, reason: 'LocationService abstraction not found');
      return hit.first.readAsStringSync();
    }

    test('it declares permission, current location and navigation', () {
      final source = serviceSource();
      expect(source, contains('abstract class LocationService'));
      expect(source, contains('requestPermission'));
      expect(source, contains('getCurrentLocation'));
      expect(source, contains('isGpsEnabled'));
    });

    test('the service interface itself does not import the plugin', () {
      // The seam has to be SDK-free, exactly like MapAdapter. If the interface
      // names Geolocator types, the abstraction has already leaked and no
      // discipline downstream recovers it.
      expect(
        serviceSource().contains('package:geolocator'),
        isFalse,
        reason: 'LocationService is the seam — it must not import the plugin',
      );
    });

    test('there is exactly one implementation wired to the provider', () {
      // Two implementations registered for the same provider would make
      // "where is the customer's real location?" unanswerable.
      final source = serviceSource();
      expect(source, contains('locationServiceProvider'));
      expect(
        RegExp('locationServiceProvider').allMatches(source).length,
        1,
        reason: 'the provider should be declared exactly once',
      );
    });
  });
}
