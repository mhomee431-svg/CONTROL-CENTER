import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/view/view_boundary.dart';

/// Files that currently break the View rule, with the reason each is allowed for
/// now. This is a BASELINE, not a permission: an entry must be removed as each
/// view is migrated, and the test below fails if a file that is NOT listed
/// starts importing `data/`.
const Map<String, String> _knownViolations = {
  'login_screen.dart':
      'Phone normalisation is a pure function, not data access. Move to '
      'domain/ as part of the auth ViewModel migration.',
  'register_screen.dart': 'Same as login_screen.dart.',
  'delete_account_screen.dart':
      'Calls phoneAuthService directly. Needs an account-deletion ViewModel.',
  'barcode_scan_screen.dart':
      'Reads permission status directly. Needs a barcode ViewModel.',
  'barcode_camera_gate.dart': 'Same as barcode_scan_screen.dart.',
  'help_support_screen.dart':
      'Calls supportRepository.submitIssue from the view. This is the clearest '
      'ViewModel violation: mutation state lives in the widget as setState.',
};

void main() {
  group('VIEW RULE enforcement', () {
    test('no view imports a data/ layer', () {
      final libDir = _findLibDir();
      final offenders = <String>[];

      for (final file in _dartFiles(libDir)) {
        if (!file.path.contains(RegExp(r'[\/\\](screens|widgets)[\/\\]'))) {
          continue;
        }
        final source = file.readAsStringSync();
        final dataImport = RegExp(
          r'''import\s+['"].*?(\/|\\)(data)[\/\\][a-z0-9_]+\.dart['"]''',
        ).firstMatch(source);

        if (dataImport != null) {
          final name = file.uri.pathSegments.last;
          if (!_knownViolations.containsKey(name)) {
            offenders.add(file.path);
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'These views reach into data/. Per the View rule, data access '
            'belongs in a ViewModel.\n${ViewBoundary.rule}\n\n'
            'Either move the access behind a ViewModel, or — if the import is a '
            'genuinely pure helper — move that helper to domain/ and import it '
            'from there.\n\nOffenders:\n${offenders.join('\n')}',
      );
    });

    test('every known violation is still justified (no stale entries)', () {
      final libDir = _findLibDir();

      for (final name in _knownViolations.keys) {
        // Match the same way the rule test above does, so the two checks can
        // never disagree: an import may be relative (`../../data/x.dart`) or
        // package-absolute (`package:app/.../data/x.dart`).
        final stillOffends = _dartFiles(libDir).any((f) {
          if (f.uri.pathSegments.last != name) return false;
          return RegExp(
            r'''import\s+['"].*?(\/|\\)(data)[\/\\][a-z0-9_]+\.dart['"]''',
          ).hasMatch(f.readAsStringSync());
        });

        expect(
          stillOffends,
          isTrue,
          reason:
              '$name is listed as a known View-rule violation but no longer '
              'violates it. Delete its entry from _knownViolations so the '
              'baseline stays honest.',
        );
      }
    });

    test('a ViewModel never imports material.dart or holds a BuildContext', () {
      final vmDir = Directory(
        '${_findLibDir().path}${Platform.pathSeparator}view',
      );
      if (!vmDir.existsSync()) return;

      final offenders = <String>[];
      for (final file in _dartFiles(vmDir)) {
        final source = file.readAsStringSync();
        if (source.contains("package:flutter/material.dart") ||
            source.contains('BuildContext') ||
            source.contains('setState')) {
          offenders.add(file.uri.pathSegments.last);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'ViewModels manage state, not pixels. Importing material.dart '
            'means rendering logic has leaked into a ViewModel.\n'
            '${ViewModelBoundary.rule}',
      );
    });
  });
}

Directory _findLibDir() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final candidate = Directory('${dir.path}${Platform.pathSeparator}lib');
    if (candidate.existsSync()) return candidate;
    dir = dir.parent;
  }
  throw StateError('Could not locate lib/ from ${Directory.current.path}');
}

Iterable<File> _dartFiles(Directory dir) sync* {
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      yield entity;
    }
  }
}
