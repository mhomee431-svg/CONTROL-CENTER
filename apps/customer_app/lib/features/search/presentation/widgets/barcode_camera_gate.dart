import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/permissions/widgets/permission_prompt_view.dart';
import '../controllers/barcode_scanner_view_model.dart';

/// Every camera-permission string in one place.
///
/// WHY A CLASS: the rationale the customer reads must be the same sentence the
/// tests assert, on every state of the flow. Copy that lives inside three
/// `build` branches drifts the moment one of them is edited.
abstract final class BarcodeCameraCopy {
  /// The one-sentence explanation shown BEFORE the OS dialog.
  static const String rationale =
      'Camera access is needed to scan product barcodes.';

  static const String deniedTitle = 'Camera permission needed';
  static const String deniedDetail =
      'Without it you can still find the same shops by typing the barcode by '
      'hand or searching by product name.';
  static const String allow = 'Allow Camera';
  static const String manual = 'Enter Barcode Manually';

  static const String blockedTitle = 'Camera is blocked for this app';
  static const String blockedDetail =
      'Turning the camera on is a device setting: the app cannot switch it '
      'back on for you.';
  static const String openSettings = 'Open System Settings';
  static const String recheck = 'Check Again';

  /// The exact system-settings path, as a checklist for the blocked state.
  static const List<String> settingsPath = [
    'Open your phone Settings > Apps > Hyperlocal Customer App',
    'Open Permissions > Camera and choose "Allow"',
    'Return to the app and tap "Check Again"',
  ];

  static const String errorTitle = 'Camera permission error';
  static const String errorDetail =
      'Could not verify camera permission. You can retry or enter the barcode manually.';
  static const String retry = 'Retry';
}

/// Owns the whole camera-permission conversation for barcode scanning.
///
/// Flow:
///   1. FIRST OPEN — the rationale is rendered and the permission is requested
///      right away, so the customer can read why the dialog appeared.
///   2. GRANTED — [cameraBuilder] is built, and only then, so the camera is
///      never started before the grant (which is what produces an unexplained
///      second system dialog).
///   3. DENIED — "Allow Camera" (ask again) plus "Enter Barcode Manually".
///   4. PERMANENTLY DENIED / RESTRICTED — system-settings guidance, with "Open
///      System Settings", a "Check Again" re-read for when the customer comes
///      back, and manual entry as the last way out.
///
/// The gate never dead-ends: manual entry is offered in every failing state,
/// which is what keeps barcode search usable without a camera at all.
class BarcodeCameraGate extends ConsumerStatefulWidget {
  const BarcodeCameraGate({
    super.key,
    required this.cameraBuilder,
    required this.onEnterManually,
  });

  /// The live-camera subtree. Built ONLY once the permission is granted.
  final WidgetBuilder cameraBuilder;

  /// Opens the manual-entry sheet — the fallback that always exists.
  final VoidCallback onEnterManually;

  @override
  ConsumerState<BarcodeCameraGate> createState() => _BarcodeCameraGateState();
}

class _BarcodeCameraGateState extends ConsumerState<BarcodeCameraGate> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(barcodeScannerViewModelProvider.notifier).checkPermission();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(barcodeScannerViewModelProvider);
    final status = state.permissionStatus;

    if (status == BarcodeCameraPermissionStatus.ready) {
      return widget.cameraBuilder(context);
    }

    final manual = PermissionPromptAction(
      key: const Key('barcode_camera_manual'),
      label: BarcodeCameraCopy.manual,
      icon: Icons.keyboard_alt_outlined,
      onPressed: widget.onEnterManually,
    );

    if (status == BarcodeCameraPermissionStatus.blocked) {
      return PermissionPromptView(
        icon: Icons.no_photography_outlined,
        title: BarcodeCameraCopy.blockedTitle,
        message:
            '${BarcodeCameraCopy.rationale}\n\n${BarcodeCameraCopy.blockedDetail}',
        bullets: BarcodeCameraCopy.settingsPath,
        primary: PermissionPromptAction(
          key: const Key('barcode_camera_open_settings'),
          label: BarcodeCameraCopy.openSettings,
          icon: Icons.settings_outlined,
          onPressed: () => ref
              .read(barcodeScannerViewModelProvider.notifier)
              .openSystemSettings(),
        ),
        fallbacks: [
          PermissionPromptAction(
            key: const Key('barcode_camera_recheck'),
            label: BarcodeCameraCopy.recheck,
            icon: Icons.refresh,
            onPressed: () => ref
                .read(barcodeScannerViewModelProvider.notifier)
                .recheckPermission(),
          ),
          manual,
        ],
      );
    }

    if (status == BarcodeCameraPermissionStatus.error) {
      return PermissionPromptView(
        icon: Icons.error_outline,
        title: BarcodeCameraCopy.errorTitle,
        message:
            '${BarcodeCameraCopy.rationale}\n\n${BarcodeCameraCopy.errorDetail}',
        primary: PermissionPromptAction(
          key: const Key('barcode_camera_retry'),
          label: BarcodeCameraCopy.retry,
          icon: Icons.refresh,
          onPressed: () => ref
              .read(barcodeScannerViewModelProvider.notifier)
              .checkPermission(),
        ),
        fallbacks: [manual],
      );
    }

    final denied = status == BarcodeCameraPermissionStatus.denied;
    return PermissionPromptView(
      icon: Icons.photo_camera_outlined,
      title: denied ? BarcodeCameraCopy.deniedTitle : 'Camera permission',
      message: denied
          ? '${BarcodeCameraCopy.rationale}\n\n${BarcodeCameraCopy.deniedDetail}'
          : '${BarcodeCameraCopy.rationale}\n\nWaiting for your answer…',
      busy: state.isBusy,
      primary: PermissionPromptAction(
        key: const Key('barcode_camera_allow'),
        label: BarcodeCameraCopy.allow,
        icon: Icons.photo_camera_outlined,
        onPressed: () => ref
            .read(barcodeScannerViewModelProvider.notifier)
            .requestPermission(),
      ),
      fallbacks: [manual],
    );
  }
}
