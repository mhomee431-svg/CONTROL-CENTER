import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show LocationPermission;
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/core/permissions/data/permission_service.dart';
import 'package:hyperlocal_shopkeeper_app/core/permissions/permission_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/account/presentation/screens/notification_settings_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/barcode/presentation/widgets/camera_permission_gate.dart';
import 'package:hyperlocal_shopkeeper_app/features/dashboard/data/dashboard_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/data/inventory_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/data/import_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/notifications/data/notifications_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/data/product_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/data/holiday_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/data/location_service.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/presentation/controllers/location_capture_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/presentation/screens/location_capture_screen.dart';

import 'fakes.dart';

/// Scripted position source — no platform channels, deterministic outcomes.
/// Mirrors the one in `location_permission_flow_test.dart`; duplicated here so
/// this suite stays self-contained rather than importing a private fake.
class _ScriptedSource implements PositionSource {
  _ScriptedSource(this.permission, {this.serviceEnabled = true});

  final LocationPermission permission;
  final bool serviceEnabled;

  @override
  Future<LocationPermissionStatus> resolvePermission() async =>
      LocationPermissionStatus(
        serviceEnabled: serviceEnabled,
        permission: permission,
      );

  @override
  Future<GpsReading> readOnce({Duration? timeLimit}) async => GpsReading(
        latitude: 25.5941,
        longitude: 85.1376,
        timestamp: DateTime.now(),
        accuracy: 8,
      );

  @override
  Stream<GpsReading> readStream({required int distanceFilterMeters}) async* {}
}

/// Spec §134 PERMISSION TESTS, one group per named case: camera denied, camera
/// permanently denied, location denied, location unavailable, notification
/// denied — plus the rule that makes the section more than a list:
///
///   "Every permission denial must have a usable alternative where possible."
///
/// Each named case was already covered by its own module's suite. What was NOT
/// covered is the INVARIANT, and that is the part that rots: a screen can drop
/// its manual-entry button and every existing test still passes, because each one
/// only ever looked at its own screen. Every group here therefore asserts the
/// same thing on a DIFFERENT gate — the denial must leave the shopkeeper a way to
/// finish the job they opened the screen for.
void main() {
  /// Returns the CONCRETE fake, not the interface: tests need `setStatus` (the
  /// shopkeeper granting from the system settings) and `requestsFor` (proving a
  /// permanent denial is never re-asked).
  InMemoryPermissionService cameraService(PermissionOutcome outcome) =>
      InMemoryPermissionService(
        statuses: {PermissionKind.camera: outcome},
        requestOutcomes: {PermissionKind.camera: outcome},
      );

  /// Everything the three permission-bearing screens read on open. Overridden in
  /// every test so no group can fail on an unrelated missing repository.
  ProviderContainer makeContainer({
    required PermissionService permissions,
    LocationService? location,
  }) {
    final container = ProviderContainer(overrides: [
      permissionServiceProvider.overrideWithValue(permissions),
      tokenStoreProvider.overrideWithValue(
          InMemoryTokenStore(accessToken: 'test-access-token')),
      selectedShopProvider
          .overrideWith(() => SelectedShopOverride(ownerShop(id: 10))),
      if (location != null) locationServiceProvider.overrideWithValue(location),
      dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepo()),
      notificationsRepositoryProvider
          .overrideWithValue(FakeNotificationsRepo()),
      productRepositoryProvider.overrideWithValue(FakeProductRepo()),
      inventoryRepositoryProvider.overrideWithValue(FakeProductRepo()),
      inventoryImportRepositoryProvider.overrideWithValue(FakeImportRepo()),
      holidayRepositoryProvider.overrideWithValue(FakeHolidayRepository()),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  void sizeUp(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pumpCameraGate(
    WidgetTester tester,
    PermissionService permissions, {
    VoidCallback? onEnterManually,
  }) async {
    sizeUp(tester);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: makeContainer(permissions: permissions),
      child: MaterialApp(
        home: BarcodeCameraGate(
          onEnterManually: onEnterManually ?? () {},
          cameraBuilder: (_) => const Text('camera'),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  // ── §134: camera denied ───────────────────────────────────────────────────
  group('camera denied', () {
    testWidgets('offers manual entry, so the shop can still add a product',
        (tester) async {
      var cameraBuilt = false;
      var manual = 0;
      sizeUp(tester);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: makeContainer(
          permissions: cameraService(PermissionOutcome.denied),
        ),
        child: MaterialApp(
          home: BarcodeCameraGate(
            onEnterManually: () => manual++,
            cameraBuilder: (_) {
              cameraBuilt = true;
              return const Text('camera');
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Denied: the live camera must NOT be built.
      expect(cameraBuilt, isFalse);
      expect(find.text('Camera permission needed'), findsOneWidget);
      // THE ALTERNATIVE: typing the barcode by hand reaches the same flow.
      expect(find.byKey(const Key('camera_permission_manual')), findsOneWidget);
      expect(find.text(CameraPermissionCopy.manual), findsOneWidget);

      await tester.tap(find.byKey(const Key('camera_permission_manual')));
      expect(manual, 1);
    });

    testWidgets('re-asks once, and a later grant opens the camera',
        (tester) async {
      final permissions = InMemoryPermissionService(
        statuses: {PermissionKind.camera: PermissionOutcome.denied},
        requestOutcomes: {PermissionKind.camera: PermissionOutcome.denied},
      );
      await pumpCameraGate(tester, permissions);
      // The gate asked once on open and was refused.
      expect(permissions.requestsFor(PermissionKind.camera), 1);
      expect(find.byKey(const Key('camera_permission_allow')), findsOneWidget);

      // The shopkeeper taps "Allow Camera" and this time says yes.
      permissions.scriptRequest(PermissionKind.camera, PermissionOutcome.granted);
      await tester.tap(find.byKey(const Key('camera_permission_allow')));
      await tester.pumpAndSettle();

      expect(permissions.requestsFor(PermissionKind.camera), 2);
      expect(find.text('camera'), findsOneWidget);
    });
  });

  // ── §134: camera permanently denied ───────────────────────────────────────
  group('camera permanently denied', () {
    testWidgets('gives settings guidance AND still offers manual entry',
        (tester) async {
      // A permanent denial must not dead-end: the OS will never show a dialog
      // again, so the only route to the camera is settings — but the FEATURE
      // (adding a product by barcode) must stay reachable.
      await pumpCameraGate(
        tester,
        cameraService(PermissionOutcome.permanentlyDenied),
      );

      expect(find.text(CameraPermissionCopy.blockedTitle), findsOneWidget);
      expect(find.byKey(const Key('camera_permission_open_settings')),
          findsOneWidget);
      expect(find.byKey(const Key('camera_permission_recheck')), findsOneWidget);
      // The alternative survives the permanent denial.
      expect(find.byKey(const Key('camera_permission_manual')), findsOneWidget);
      // And no "Allow Camera" that could only ever resolve to the same refusal.
      expect(find.byKey(const Key('camera_permission_allow')), findsNothing);
    });

    testWidgets('"Check Again" picks up a grant made in the system settings',
        (tester) async {
      final permissions = cameraService(PermissionOutcome.permanentlyDenied);
      await pumpCameraGate(tester, permissions);

      // The shopkeeper leaves for Settings, grants, and comes back.
      permissions.setStatus(PermissionKind.camera, PermissionOutcome.granted);
      await tester.tap(find.byKey(const Key('camera_permission_recheck')));
      await tester.pumpAndSettle();

      expect(find.text('camera'), findsOneWidget);
    });

    testWidgets('a policy restriction is treated like a permanent denial',
        (tester) async {
      // `restricted` means the app may not even ask (parental controls / MDM).
      final permissions = cameraService(PermissionOutcome.restricted);
      await pumpCameraGate(tester, permissions);

      expect(find.text(CameraPermissionCopy.blockedTitle), findsOneWidget);
      expect(find.byKey(const Key('camera_permission_manual')), findsOneWidget);
      // Never asked: the platform would refuse the request outright.
      expect(permissions.requestsFor(PermissionKind.camera), 0);
    });
  });

  // ── §134: location denied / location unavailable ───────────────────────────
  group('location denied and location unavailable', () {
    Future<void> pumpLocation(
      WidgetTester tester,
      LocationPermission permission, {
      bool serviceEnabled = true,
    }) async {
      sizeUp(tester);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: makeContainer(
          permissions: cameraService(PermissionOutcome.granted),
          location: LocationService(
            positionSource: _ScriptedSource(permission,
                serviceEnabled: serviceEnabled),
            settingsOpener: RecordingSettingsOpener(),
          ),
        ),
        child: const MaterialApp(home: LocationCaptureScreen()),
      ));
      // Flush the microtask that kicks off startCapture().
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
    }

    /// The two fallbacks that need neither the grant nor GPS.
    void expectBothFallbacks() {
      expect(find.text('Choose Location on Map'), findsOneWidget);
      expect(find.text('Enter Address Manually'), findsOneWidget);
    }

    testWidgets('a plain denial offers both fallbacks and can still be retried',
        (tester) async {
      // Denied (not forever): the OS will ask again, so the screen must offer
      // "Allow Location" as well as the two manual paths.
      await pumpLocation(tester, LocationPermission.denied);

      expect(find.text('Choose Location on Map'), findsOneWidget);
      expect(find.text('Enter Address Manually'), findsOneWidget);
      expect(find.byKey(const Key('location_permission_primary')), findsOneWidget);
    });

    testWidgets('a permanent denial still offers both fallbacks', (tester) async {
      await pumpLocation(tester, LocationPermission.deniedForever);

      expectBothFallbacks();
      // The only route back to GPS is the system settings page.
      expect(find.text('Location permission is blocked'), findsOneWidget);
    });

    testWidgets('location services being off is NOT a dead end', (tester) async {
      // "Location unavailable" — the grant is fine, the radio is off. Toggling
      // GPS is a device setting, so the manual paths must carry the flow.
      await pumpLocation(
        tester,
        LocationPermission.whileInUse,
        serviceEnabled: false,
      );

      expect(find.textContaining('Location services are turned off'),
          findsOneWidget);
      expect(find.text('Turn On Location Services'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
      expectBothFallbacks();
    });

    testWidgets('"Choose Location on Map" completes the job with no GPS',
        (tester) async {
      // The alternative must not merely be VISIBLE, it must WORK: a hand-placed
      // pin is confirmable and claims no invented accuracy.
      await pumpLocation(tester, LocationPermission.denied);

      await tester.tap(find.text('Choose Location on Map'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Place your shop pin'), findsOneWidget);
      expect(find.textContaining('No GPS fix'), findsOneWidget);
      expect(find.textContaining('Accuracy: '), findsNothing);

      // Let the hint snackbar time out so no timer outlives the test.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });

  // ── §134: notification denied ─────────────────────────────────────────────
  group('notification denied', () {
    Future<void> pumpNotifications(
      WidgetTester tester,
      PermissionService permissions,
    ) async {
      sizeUp(tester);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: makeContainer(permissions: permissions),
        child: const MaterialApp(home: NotificationSettingsScreen()),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('never blocks the app: alerts keep arriving in the Alerts tab',
        (tester) async {
      // §82 "Do not block the entire app when notifications are denied." The
      // alternative for notifications IS the in-app Alerts tab, which is on by
      // construction — so a denial must leave the rest of Settings usable.
      await pumpNotifications(
        tester,
        InMemoryPermissionService(
          statuses: {PermissionKind.notifications: PermissionOutcome.denied},
        ),
      );

      // The denial is reported honestly...
      expect(find.byKey(const Key('notification_permission_status')),
          findsOneWidget);
      expect(find.text('Not allowed'), findsOneWidget);
      // ...and "Enable Notifications" is right there (§82's required action).
      expect(find.byKey(const Key('notification_enable_button')), findsOneWidget);

      // THE ALTERNATIVE: the Alerts tab is unaffected, and says so.
      expect(find.text('Alerts tab'), findsOneWidget);
      expect(find.text('Always on'), findsOneWidget);
      // Everything else on the screen still renders.
      expect(find.byKey(const Key('notification_settings_edit_preferences')),
          findsOneWidget);
    });

    testWidgets('a permanent denial routes to the system settings instead',
        (tester) async {
      await pumpNotifications(
        tester,
        InMemoryPermissionService(
          statuses: {PermissionKind.notifications: PermissionOutcome.denied},
          requestOutcomes: {
            PermissionKind.notifications: PermissionOutcome.permanentlyDenied,
          },
        ),
      );

      // Asking again resolved to a permanent denial, so the status must follow
      // it and the settings button must appear.
      await tester.tap(find.byKey(const Key('notification_enable_button')));
      await tester.pumpAndSettle();

      expect(find.text('Blocked'), findsOneWidget);
      expect(find.byKey(const Key('notification_open_settings_button')),
          findsOneWidget);
      // The Alerts tab alternative is still there.
      expect(find.text('Always on'), findsOneWidget);
    });

    testWidgets('an unreadable platform status is not treated as a denial',
        (tester) async {
      // Desktop / web builds cannot report a permission. That must NOT read as
      // "Not allowed" — the app would nag for a grant it can never obtain.
      await pumpNotifications(
        tester,
        InMemoryPermissionService(
          statuses: {PermissionKind.notifications: PermissionOutcome.unknown},
        ),
      );

      expect(find.text('Unknown'), findsOneWidget);
      expect(find.text('Not allowed'), findsNothing);
    });
  });
}