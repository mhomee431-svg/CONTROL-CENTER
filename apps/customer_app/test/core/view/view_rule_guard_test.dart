import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/view/view_boundary.dart';

/// Files that currently break the View rule, with the reason each is allowed for
/// now. This is a BASELINE, not a permission: an entry must be removed as each
/// view is migrated, and the test below fails if a file that is NOT listed
/// starts importing `data/`, or if a listed file STOPS violating — so the
/// baseline cannot quietly rot.
///
/// Already fixed (removed from this list, kept here as a record):
///   login_screen.dart, register_screen.dart — imported `data/phone_utils.dart`.
///     Phone normalisation is a pure function, so it moved to
///     `auth/domain/phone_utils.dart` with no logic change.
///   help_support_screen.dart — called `supportRepository.submitIssue` from the
///     view and tracked `_isSubmitting`/`_error`/`_submitted` as three
///     `setState` fields. A `SupportFormViewModel` now owns a `MutationState`.
///   delete_account_screen.dart — already depends on `auth/domain/`, not a data
///     layer. (The stale-baseline test below is what surfaced this: the list
///     claimed a violation that no longer existed.)
const Map<String, String> _knownViolations = {
  'barcode_scan_screen.dart':
      'Reads permission status directly. Needs a barcode ViewModel.',
  'barcode_camera_gate.dart': 'Same as barcode_scan_screen.dart.',
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

  group('STATE MANAGEMENT: one approach only', () {
    test('no competing state-management framework is introduced', () {
      // The state-management rule says to KEEP the existing approach. Riverpod
      // is the existing approach, and the audit found it is the ONLY one in use
      // (0 ChangeNotifier, 0 StateProvider, 0 get/bloc/provider). This test is
      // what keeps that true: a new package becomes a reviewable, deliberate
      // change instead of a gradual drift into a mixed codebase.
      //
      // Deliberately NOT flagged:
      //   * `setState` — local widget state (a controller's text, an expanded
      //     tile) is the correct place for it.
      //   * `ValueListenableBuilder` — required by the third-party
      //     `mobile_scanner` camera API, not our own state.
      const forbidden = [
        'package:flutter_bloc',
        'package:bloc',
        'package:get/get.dart',
        'package:provider/provider.dart',
        'package:redux',
        'package:mobx',
        'package:hooks_riverpod', // hooks are a different mental model
      ];

      final offenders = <String, List<String>>{};
      for (final file in _dartFiles(_findLibDir())) {
        final source = file.readAsStringSync();
        for (final pkg in forbidden) {
          if (source.contains("import '$pkg'")) {
            offenders
                .putIfAbsent(file.uri.pathSegments.last, () => <String>[])
                .add(pkg);
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'A second state-management framework means two mental models for '
            'the same problem. Use Riverpod, or justify the change explicitly '
            'before adding the dependency.',
      );
    });

    test('no feature state class reintroduces the boolean-cluster antipattern', () {
      // A lifecycle described by several independent `bool` fields is what the
      // ViewModel rule forbids: the fields can contradict each other (loading
      // AND error AND empty). Sealed types are the sanctioned replacement.
      //
      // Deliberately narrow, so it flags real lifecycles rather than demanding
      // ceremony: scoped to feature `*_state.dart` files outside views, because
      // a widget owning one or two booleans of local UI state is fine.
      final offenders = <String>[];
      for (final file in _dartFiles(_findLibDir())) {
        final path = file.path.replaceAll('\\', '/');
        if (!path.contains('/lib/features/')) continue;
        if (path.contains('/presentation/screens/') ||
            path.contains('/presentation/widgets/')) {
          continue; // views: one or two bools is fine
        }
        if (!path.endsWith('_state.dart') && !path.endsWith('state.dart')) {
          continue;
        }

        final boolFields = RegExp(
          r'^\s*final\s+bool\s+\w+\s*;',
          multiLine: true,
        ).allMatches(file.readAsStringSync()).length;

        if (boolFields >= 3) {
          offenders.add(
            '${file.uri.pathSegments.last} ($boolFields independent bool fields)',
          );
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'A lifecycle described by 3+ independent booleans can hold '
            'contradictory values (loading AND error AND empty). Use a sealed '
            'state type instead.\n${ViewModelBoundary.rule}',
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
