import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/permissions/data/permission_service.dart';
import 'package:hyperlocal_shopkeeper_app/core/permissions/permission_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/barcode/presentation/widgets/camera_permission_gate.dart';

/// Runtime-permission flows: the barcode camera gate and the shared permission
/// vocabulary (the notification flow is covered in
/// `notification_permission_test.dart`).
///
/// WHY: every one of these flows has an outcome for each answer the OS can give
/// (granted / denied / permanently denied) PLUS a way forward that needs no
/// permission at all. A permission screen is exactly where an app silently
/// dead-ends in production, so all of them are pinned here.
void main() {
  group('PermissionOutcome vocabulary', () {
    test('granted and limited are usable; a plain denial stays askable', () {
      expect(PermissionOutcome.granted.isGranted, isTrue);
      expect(PermissionOutcome.limited.isGranted, isTrue);
      expect(PermissionOutcome.granted.label, 'Allowed');

      expect(PermissionOutcome.denied.isGranted, isFalse);
      expect(PermissionOutcome.denied.canAskAgain, isTrue);
      expect(PermissionOutcome.denied.needsSystemSettings, isFalse);
      expect(PermissionOutcome.denied.label, 'Not allowed');
    });

    test('a permanent denial and a policy lock are NOT askable again', () {
      for (final outcome in [
        PermissionOutcome.permanentlyDenied,
        PermissionOutcome.restricted,
      ]) {
        expect(outcome.canAskAgain, isFalse, reason: '$outcome');
        expect(outcome.needsSystemSettings, isTrue, reason: '$outcome');
        expect(outcome.label, 'Blocked', reason: '$outcome');
      }
    });

    test('unknown never pretends to be a denial', () {
      // A platform that cannot report a status (web/desktop) must keep the
      // feature usable instead of inventing a refusal.
      expect(PermissionOutcome.unknown.isGranted, isFalse);
      expect(PermissionOutcome.unknown.canAskAgain, isTrue);
      expect(PermissionOutcome.unknown.needsSystemSettings, isFalse);
    });
  });

  group('InMemoryPermissionService', () {
    test('request records the call and settles the status', () async {
      final service = InMemoryPermissionService(
        statuses: {PermissionKind.camera: PermissionOutcome.denied},
        requestOutcomes: {PermissionKind.camera: PermissionOutcome.granted},
      );

      expect((await service.status(PermissionKind.camera)).outcome,
          PermissionOutcome.denied);
      expect((await service.request(PermissionKind.camera)).outcome,
          PermissionOutcome.granted);
      // The next status read must agree with what the shopkeeper answered.
      expect((await service.status(PermissionKind.camera)).outcome,
          PermissionOutcome.granted);
      expect(service.requestsFor(PermissionKind.camera), 1);
      expect(service.requestsFor(PermissionKind.notifications), 0);
    });

    test('openSystemSettings is counted, never thrown', () async {
      final service = InMemoryPermissionService();
      expect(await service.openSystemSettings(), isTrue);
      expect(service.openSettingsCalls, 1);

      service.settingsOpenResult = false;
      expect(await service.openSystemSettings(), isFalse);
      expect(service.openSettingsCalls, 2);
    });
  });

  group('BarcodeCameraGate (camera permission)', () {
    /// Pumps the gate over a scripted permission service and flushes the
    /// status read + request microtasks. `pumpAndSettle` cannot be used while
    /// a request is in flight: the busy bar animates forever.
    Future<void> pumpGate(
      WidgetTester tester,
      InMemoryPermissionService permissions, {
      VoidCallback? onManual,
    }) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [permissionServiceProvider.overrideWithValue(permissions)],
        child: MaterialApp(
          home: Scaffold(
            body: BarcodeCameraGate(
              cameraBuilder: (_) => const Text('live camera'),
              onEnterManually: onManual ?? () {},
            ),
          ),
        ),
      ));
      await tester.pump(); // initState microtask
      await tester.pump(const Duration(milliseconds: 20)); // status + request
      await tester.pump(const Duration(milliseconds: 20)); // rebuild
    }

    testWidgets('first open: explains why, then asks for the permission',
        (tester) async {
      final permissions = InMemoryPermissionService(
        requestOutcomes: {PermissionKind.camera: PermissionOutcome.denied},
      );
      await pumpGate(tester, permissions);

      // The explanation is on screen while the permission is requested, and
      // the OS dialog was triggered exactly once.
      expect(find.textContaining(CameraPermissionCopy.rationale), findsWidgets);
      expect(permissions.requestsFor(PermissionKind.camera), 1);

      // Refused → the two actions the contract names.
      expect(find.text('Allow Camera'), findsOneWidget);
      expect(find.text('Enter Barcode Manually'), findsOneWidget);
      // The camera is never built without the grant.
      expect(find.text('live camera'), findsNothing);
    });

    testWidgets('a denial never dead-ends: manual entry stays reachable',
        (tester) async {
      var manual = 0;
      final permissions = InMemoryPermissionService(
        requestOutcomes: {PermissionKind.camera: PermissionOutcome.denied},
      );
      await pumpGate(tester, permissions, onManual: () => manual++);

      await tester.tap(find.byKey(const Key('camera_permission_manual')));
      await tester.pump();
      expect(manual, 1);
    });

    testWidgets('"Allow Camera" re-asks, and a grant opens the camera',
        (tester) async {
      final permissions = InMemoryPermissionService(
        requestOutcomes: {PermissionKind.camera: PermissionOutcome.denied},
      );
      await pumpGate(tester, permissions);
      expect(permissions.requestsFor(PermissionKind.camera), 1);

      permissions.scriptRequest(
          PermissionKind.camera, PermissionOutcome.granted);
      await tester.tap(find.byKey(const Key('camera_permission_allow')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(permissions.requestsFor(PermissionKind.camera), 2);
      expect(find.text('live camera'), findsOneWidget);
      expect(find.text('Allow Camera'), findsNothing);
    });

    testWidgets('an already granted camera asks for nothing', (tester) async {
      final permissions = InMemoryPermissionService(
        statuses: {PermissionKind.camera: PermissionOutcome.granted},
      );
      await pumpGate(tester, permissions);

      expect(find.text('live camera'), findsOneWidget);
      expect(permissions.requestsFor(PermissionKind.camera), 0);
    });

    testWidgets('an unreadable platform status still opens the camera',
        (tester) async {
      final permissions = InMemoryPermissionService(
        statuses: {PermissionKind.camera: PermissionOutcome.unknown},
      );
      await pumpGate(tester, permissions);

      // Web/desktop builds cannot report a status; the gate must not invent a
      // refusal there — the scanner's own error view reports real failures.
      expect(find.text('live camera'), findsOneWidget);
      expect(permissions.requestsFor(PermissionKind.camera), 0);
    });

    testWidgets('permanently denied: settings guidance, no pointless re-ask',
        (tester) async {
      var manual = 0;
      final permissions = InMemoryPermissionService(
        statuses: {PermissionKind.camera: PermissionOutcome.permanentlyDenied},
      );
      await pumpGate(tester, permissions, onManual: () => manual++);

      expect(find.text(CameraPermissionCopy.blockedTitle), findsOneWidget);
      // Asking again cannot work, so the gate does not even try.
      expect(permissions.requestsFor(PermissionKind.camera), 0);
      for (final step in CameraPermissionCopy.settingsPath) {
        expect(find.text(step), findsOneWidget, reason: step);
      }

      // The system-settings escape hatch is a real call.
      await tester.tap(find.byKey(const Key('camera_permission_open_settings')));
      await tester.pump();
      expect(permissions.openSettingsCalls, 1);

      // Manual entry exists before the grant as well.
      await tester.tap(find.byKey(const Key('camera_permission_manual')));
      await tester.pump();
      expect(manual, 1);
    });

    testWidgets('"Check Again" picks up a grant made in the system settings',
        (tester) async {
      final permissions = InMemoryPermissionService(
        statuses: {PermissionKind.camera: PermissionOutcome.permanentlyDenied},
      );
      await pumpGate(tester, permissions);
      expect(find.text(CameraPermissionCopy.blockedTitle), findsOneWidget);

      // The shopkeeper allowed the camera in the phone settings meanwhile.
      permissions.setStatus(PermissionKind.camera, PermissionOutcome.granted);
      await tester.tap(find.byKey(const Key('camera_permission_recheck')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(find.text('live camera'), findsOneWidget);
    });
  });
}
