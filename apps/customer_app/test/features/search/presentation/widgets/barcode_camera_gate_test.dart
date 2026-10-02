import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hyperlocal_app/core/permissions/data/permission_service.dart';
import 'package:hyperlocal_app/core/permissions/permission_models.dart';
import 'package:hyperlocal_app/features/search/presentation/widgets/barcode_camera_gate.dart';

/// Pumps the real gate with a scripted permission service.
///
/// The gate builds its camera subtree only after the grant, so tests assert on
/// that subtree instead of a real `MobileScanner`: no camera, no channels.
Future<InMemoryPermissionService> pumpGate(
  WidgetTester tester, {
  Map<PermissionKind, PermissionOutcome>? statuses,
  Map<PermissionKind, PermissionOutcome>? requestOutcomes,
}) async {
  final permissions = InMemoryPermissionService(
    statuses: statuses,
    requestOutcomes: requestOutcomes,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [permissionServiceProvider.overrideWithValue(permissions)],
      child: MaterialApp(
        home: Scaffold(
          body: BarcodeCameraGate(
            cameraBuilder: (_) =>
                const Text('camera live', key: Key('fake_camera')),
            onEnterManually: () {},
          ),
        ),
      ),
    ),
  );
  return permissions;
}

class _FailingPermissionService implements PermissionService {
  _FailingPermissionService(this.inner, this.shouldThrow);

  final InMemoryPermissionService inner;
  final bool Function() shouldThrow;

  @override
  Future<PermissionSnapshot> status(PermissionKind kind) async {
    if (shouldThrow()) throw Exception('Platform status channel failure');
    return inner.status(kind);
  }

  @override
  Future<PermissionSnapshot> request(PermissionKind kind) async {
    if (shouldThrow()) throw Exception('Platform request channel failure');
    return inner.request(kind);
  }

  @override
  Future<bool> openSystemSettings() => inner.openSystemSettings();
}

void main() {
  testWidgets(
    'first open explains, asks once, and builds the camera on grant',
    (tester) async {
      final permissions = await pumpGate(
        tester,
        requestOutcomes: {PermissionKind.camera: PermissionOutcome.granted},
      );

      // FIRST PUMP-WAIT: the ask is in flight (`busy`), with a neutral title.
      // The customer sees movement, not a stale explanation, while the OS
      // dialog is on screen.
      expect(find.text('Camera permission'), findsOneWidget);
      expect(find.byKey(const Key('fake_camera')), findsNothing);

      await tester.pumpAndSettle();

      // …exactly one request was made…
      expect(permissions.requestsFor(PermissionKind.camera), 1);
      // …and the grant builds the camera subtree, replacing the explanation.
      expect(find.byKey(const Key('fake_camera')), findsOneWidget);
      expect(find.byKey(const Key('barcode_camera_allow')), findsNothing);
    },
  );

  testWidgets('an existing grant never triggers a request', (tester) async {
    final permissions = await pumpGate(
      tester,
      statuses: {PermissionKind.camera: PermissionOutcome.granted},
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('fake_camera')), findsOneWidget);
    expect(permissions.requestsFor(PermissionKind.camera), 0);
  });

  testWidgets('denial keeps "Allow Camera" and manual entry, both working', (
    tester,
  ) async {
    final permissions = await pumpGate(
      tester,
      requestOutcomes: {PermissionKind.camera: PermissionOutcome.denied},
    );
    await tester.pumpAndSettle();

    expect(find.text(BarcodeCameraCopy.deniedTitle), findsOneWidget);
    expect(find.byKey(const Key('fake_camera')), findsNothing);
    // Manual entry is the escape hatch that never disappears.
    expect(find.byKey(const Key('barcode_camera_manual')), findsOneWidget);

    // Tapping "Allow Camera" asks again — the ONLY path back from a denial.
    permissions.scriptRequest(PermissionKind.camera, PermissionOutcome.granted);
    await tester.tap(find.byKey(const Key('barcode_camera_allow')));
    await tester.pumpAndSettle();

    expect(permissions.requestsFor(PermissionKind.camera), 2);
    expect(find.byKey(const Key('fake_camera')), findsOneWidget);
  });

  testWidgets(
    'blocked permission guides to settings, rechecks, and manual entry',
    (tester) async {
      final permissions = await pumpGate(
        tester,
        requestOutcomes: {
          PermissionKind.camera: PermissionOutcome.permanentlyDenied,
        },
      );
      await tester.pumpAndSettle();

      expect(find.text(BarcodeCameraCopy.blockedTitle), findsOneWidget);
      // The exact settings path, so the customer is not sent hunting.
      for (final step in BarcodeCameraCopy.settingsPath) {
        expect(find.text(step), findsOneWidget);
      }
      expect(
        find.byKey(const Key('barcode_camera_open_settings')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('barcode_camera_manual')), findsOneWidget);
      expect(find.byKey(const Key('fake_camera')), findsNothing);

      await tester.tap(find.byKey(const Key('barcode_camera_open_settings')));
      await tester.pump();
      expect(permissions.openSettingsCalls, 1);

      // The customer returns from settings having allowed the camera; the
      // re-check re-reads the status WITHOUT requesting.
      permissions.setStatus(PermissionKind.camera, PermissionOutcome.granted);
      await tester.tap(find.byKey(const Key('barcode_camera_recheck')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('fake_camera')), findsOneWidget);
      expect(permissions.requestsFor(PermissionKind.camera), 1);
    },
  );

  testWidgets(
    'an unreadable status falls through to the camera, not a denial',
    (tester) async {
      await pumpGate(
        tester,
        requestOutcomes: {PermissionKind.camera: PermissionOutcome.unknown},
      );
      await tester.pumpAndSettle();

      // `unknown` means the plugin could not answer (desktop/web builds). The
      // camera gets the chance to report its own failure — which offers manual
      // entry — instead of stranding the customer on a denial.
      expect(find.byKey(const Key('fake_camera')), findsOneWidget);
    },
  );

  testWidgets('error state displays retry prompt and recovers on retry', (
    tester,
  ) async {
    final permissions = InMemoryPermissionService();
    var shouldThrow = true;
    final testService = _FailingPermissionService(
      permissions,
      () => shouldThrow,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [permissionServiceProvider.overrideWithValue(testService)],
        child: MaterialApp(
          home: Scaffold(
            body: BarcodeCameraGate(
              cameraBuilder: (_) =>
                  const Text('camera live', key: Key('fake_camera')),
              onEnterManually: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(BarcodeCameraCopy.errorTitle), findsOneWidget);
    expect(find.textContaining(BarcodeCameraCopy.errorDetail), findsOneWidget);
    expect(find.byKey(const Key('barcode_camera_retry')), findsOneWidget);
    expect(find.byKey(const Key('barcode_camera_manual')), findsOneWidget);
    expect(find.byKey(const Key('fake_camera')), findsNothing);

    // Now resolve error and retry
    shouldThrow = false;
    permissions.setStatus(PermissionKind.camera, PermissionOutcome.granted);
    await tester.tap(find.byKey(const Key('barcode_camera_retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('fake_camera')), findsOneWidget);
    expect(find.byKey(const Key('barcode_camera_retry')), findsNothing);
  });
}
