import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/permissions/data/permission_service.dart';
import '../../../../core/permissions/permission_models.dart';
import '../../../../core/permissions/widgets/permission_prompt_view.dart';

/// Every camera-permission string in one place.
///
/// WHY A CLASS: the rationale the shopkeeper reads must be the same sentence
/// the tests assert, on every state of the flow. Copy that lives inside three
/// `build` branches drifts the moment one of them is edited.
abstract final class CameraPermissionCopy {
  /// The one-sentence explanation shown BEFORE the OS dialog (barcode camera
  /// permission contract).
  static const String rationale =
      'Camera access is needed to scan product barcodes.';

  static const String deniedTitle = 'Camera permission needed';
  static const String deniedDetail =
      'Without it you can still add and update stock by typing the barcode '
      'by hand.';
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
    'Open your phone Settings > Apps > Passly Business',
    'Open Permissions > Camera and choose "Allow"',
    'Return to the app and tap "Check Again"',
  ];
}

/// Owns the whole camera-permission conversation for the barcode scanner.
///
/// Flow (barcode camera permission contract):
///   1. FIRST OPEN — the rationale is rendered and the permission is requested
///      right away, so the shopkeeper can read why the dialog appeared.
///   2. GRANTED — [cameraBuilder] is built, and only then, so the camera is
///      never started before the grant (which is what produced a second,
///      unexplained system dialog before).
///   3. DENIED — "Allow Camera" (ask again) plus "Enter Barcode Manually".
///   4. PERMANENTLY DENIED / RESTRICTED — the system-settings guidance, with
///      "Open System Settings", a "Check Again" re-read for when the
///      shopkeeper comes back, and manual entry as the last way out.
///
/// The gate never blocks the flow: manual entry is offered in every failing
/// state.
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

enum _CameraGate { asking, denied, blocked, ready }

class _BarcodeCameraGateState extends ConsumerState<BarcodeCameraGate> {
  _CameraGate _gate = _CameraGate.asking;
  bool _busy = true;

  PermissionService get _permissions => ref.read(permissionServiceProvider);

  @override
  void initState() {
    super.initState();
    Future.microtask(_start);
  }

  /// Read (never prompt) → either open the camera, go straight to the settings
  /// guidance, or explain-and-ask.
  Future<void> _start() async {
    final snapshot = await _permissions.status(PermissionKind.camera);
    if (!mounted) return;
    if (snapshot.isGranted || snapshot.outcome == PermissionOutcome.unknown) {
      // `unknown` = this platform cannot answer (web/desktop build). The camera
      // is attempted and reports its own failure through the scanner's error
      // view, instead of the app inventing a denial.
      setState(() {
        _gate = _CameraGate.ready;
        _busy = false;
      });
      return;
    }
    if (snapshot.needsSystemSettings) {
      setState(() {
        _gate = _CameraGate.blocked;
        _busy = false;
      });
      return;
    }
    await _ask();
  }

  /// Explain → request. Runs on first open and again from "Allow Camera".
  Future<void> _ask() async {
    setState(() => _busy = true);
    final result = await _permissions.request(PermissionKind.camera);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.isGranted || result.outcome == PermissionOutcome.unknown) {
        _gate = _CameraGate.ready;
      } else if (result.needsSystemSettings) {
        _gate = _CameraGate.blocked;
      } else {
        _gate = _CameraGate.denied;
      }
    });
  }

  /// Re-reads the status — the way back after the shopkeeper allowed the camera
  /// in the system settings.
  Future<void> _recheck() async {
    setState(() => _busy = true);
    final snapshot = await _permissions.status(PermissionKind.camera);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (snapshot.isGranted || snapshot.outcome == PermissionOutcome.unknown) {
        _gate = _CameraGate.ready;
      } else if (snapshot.needsSystemSettings) {
        _gate = _CameraGate.blocked;
      } else {
        _gate = _CameraGate.denied;
      }
    });
  }

  Future<void> _openSystemSettings() => _permissions.openSystemSettings();

  @override
  Widget build(BuildContext context) {
    if (_gate == _CameraGate.ready) return widget.cameraBuilder(context);

    final manual = PermissionPromptAction(
      key: const Key('camera_permission_manual'),
      label: CameraPermissionCopy.manual,
      icon: Icons.keyboard_alt_outlined,
      onPressed: widget.onEnterManually,
    );

    if (_gate == _CameraGate.blocked) {
      return PermissionPromptView(
        icon: Icons.no_photography_outlined,
        title: CameraPermissionCopy.blockedTitle,
        message: '${CameraPermissionCopy.rationale}\n\n'
            '${CameraPermissionCopy.blockedDetail}',
        bullets: CameraPermissionCopy.settingsPath,
        primary: PermissionPromptAction(
          key: const Key('camera_permission_open_settings'),
          label: CameraPermissionCopy.openSettings,
          icon: Icons.settings_outlined,
          onPressed: _openSystemSettings,
        ),
        fallbacks: [
          PermissionPromptAction(
            key: const Key('camera_permission_recheck'),
            label: CameraPermissionCopy.recheck,
            icon: Icons.refresh,
            onPressed: _recheck,
          ),
          manual,
        ],
      );
    }

    final denied = _gate == _CameraGate.denied;
    return PermissionPromptView(
      icon: Icons.photo_camera_outlined,
      title: denied ? CameraPermissionCopy.deniedTitle : 'Camera permission',
      message: denied
          ? '${CameraPermissionCopy.rationale}\n\n'
              '${CameraPermissionCopy.deniedDetail}'
          : '${CameraPermissionCopy.rationale}\n\nWaiting for your answer…',
      busy: _busy,
      primary: PermissionPromptAction(
        key: const Key('camera_permission_allow'),
        label: CameraPermissionCopy.allow,
        icon: Icons.photo_camera_outlined,
        onPressed: _ask,
      ),
      fallbacks: [manual],
    );
  }
}
