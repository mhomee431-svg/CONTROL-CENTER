# Shopkeeper App — Runtime Permission Flows

Single source of truth for every *askable* device permission the app requests,
and the exact outcome handling the product contract demands.

Shared layer: `lib/core/permissions/`
(`permission_models.dart` — `PermissionKind`, `PermissionOutcome`;
`data/permission_service.dart` — `PermissionService` + an `InMemoryPermissionService`
test double exposed as `permissionServiceProvider`).

## 1. Barcode camera

Gate: `lib/features/barcode/presentation/widgets/camera_permission_gate.dart`.

| First open | Explain: "Camera access is needed to scan product barcodes." then request. |
|---|---|
| Granted (`granted`/`limited`) | Live camera preview + scanner. |
| Denied once | Buttons: **Allow Camera** (re-asks) + **Enter Barcode Manually** (no permission needed). |
| Denied forever / restricted | System-settings guidance (`CameraPermissionCopy.settingsPath`) + **Open System Settings** + **Check Again**; **Enter Barcode Manually** stays available. |

Runtime error view (scan failed) gains **Open System Settings**.

Tests: `test/permission_flows_test.dart` — *BarcodeCameraGate* group
(explain -> ask; denied -> re-ask + manual; already granted; unknown still opens;
permanent denial -> settings + no re-ask; "Check Again" picks up a grant made
in settings).

## 2. Location (shop location)

Service: `lib/features/shops/data/location_service.dart`.
Screen: `lib/features/shops/presentation/screens/location_capture_screen.dart`.
State: `lib/features/shops/domain/location_capture_state.dart`.

| Permission state | Screen behaviour |
|---|---|
| Granted + GPS on | Fetch fix -> place pin (GPS source). |
| Denied once | **Allow Location** (re-asks) + **Choose Location on Map** + **Enter Address Manually**. |
| Denied forever / restricted | **Open System Settings** (app page) + **Choose Location on Map** + **Enter Address Manually**, plus the 3-step settings guidance ("Open your phone Settings > Apps > Passly Business ..."). |
| Location services off | **Turn On Location Services** (-> system location page) + **Try Again** + the two manual fallbacks. |

Honest provenance (`CapturedShopLocation`):
- GPS fix -> `location_source: GPS`, real `accuracy_meters`.
- Hand-placed pin / typed address -> `location_source: MANUAL`, **no** `accuracy_meters` key (never `0 m`).

Tests: `test/location_permission_flow_test.dart` (system-settings openers;
map-only fallback; GPS-off; no-permission map placement; provenance of the
captured location).

## 3. Notifications

Controller: `lib/features/notifications/presentation/controllers/notification_permission_controller.dart`.
Screen tile: `lib/features/account/presentation/screens/notification_settings_screen.dart`
(Settings -> Notification settings row).

| State | Behaviour |
|---|---|
| Granted | Shows "Notifications are allowed on this device." |
| Denied once | **Enable Notifications** (asks once) + **Open System Settings**; the screen is **never blocked**. |
| Blocked forever / restricted | **Enable Notifications** + **Open System Settings**, with "will not ask again" copy. |
| `POST_NOTIFICATIONS` (Android 13+) / `notifications` (iOS) requested at runtime only — the permission never blocks app usage. | A persistent notice at the bottom of the page: "Notifications will never block the app — you can turn them on any time from here." |

Tests: `test/notification_permission_test.dart` (controller outcome mapping
for every `PermissionOutcome`; screen renders for granted / denied / blocked;
tapping **Enable Notifications** asks exactly once and flips the status;
tapping **Open System Settings** calls the platform).

## Android / iOS config

- `AndroidManifest.xml`: `android.permission.CAMERA`,
  `android.permission.POST_NOTIFICATIONS` (Tirmanisu+),
  `android.permission.ACCESS_FINE_LOCATION` (+ foreground service) +
  `android.permission.ACCESS_COARSE_LOCATION`.
- `ios/Podfile`: `PERMISSION_CAMERA=1`,
  `PERMISSION_NOTIFICATIONS=1`, `PERMISSION_LOCATION=1`.
