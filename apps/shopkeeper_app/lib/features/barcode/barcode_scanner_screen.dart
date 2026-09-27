import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/permissions/data/permission_service.dart';
import '../products/presentation/controllers/products_controller.dart';
import '../products/presentation/widgets/product_sheets.dart';
import 'domain/barcode_models.dart';
import 'presentation/controllers/barcode_controller.dart';
import 'presentation/widgets/barcode_sheets.dart';
import 'presentation/widgets/camera_permission_gate.dart';

/// Full-screen barcode scanner with live camera feed (Phase 24).
///
/// Flow:
///   1. Camera preview fills the screen (mobile_scanner, retail formats).
///   2. On first detection → pause camera → resolve via the backend.
///   3. FOUND → confirm sheet (product, variant, price, qty) → save.
///   4. NOT_FOUND / INVALID → snackbar + manual entry option.
///   5. MULTIPLE_MATCHES → confirm sheet with the full match list.
///
/// Requires a selected shop — the router guard enforces this.
class BarcodeScannerScreen extends ConsumerStatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  ConsumerState<BarcodeScannerScreen> createState() =>
      _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends ConsumerState<BarcodeScannerScreen> {
  late MobileScannerController _cameraController;

  /// Guards against duplicate detections of the same code while a resolve
  /// round-trip is in flight.
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _cameraController = _createCameraController();
    // §112 "when reopening, initialize cleanly". The scan controller is a
    // container-scoped provider, so it outlives this screen: a session the
    // shopkeeper left by popping the scanner mid-resolve leaves the status on
    // `resolving`/`saving`, and the next open would inherit it. A fresh scanning
    // session always starts from idle.
    //
    // Deferred by a microtask because Riverpod forbids writing a provider
    // during a widget life-cycle. Nothing flickers in the meantime: the AppBar
    // spinner is driven by [_isProcessing], this screen's OWN flag, never by
    // the inherited status.
    Future.microtask(() {
      if (mounted) ref.read(barcodeControllerProvider.notifier).reset();
    });
  }

  MobileScannerController _createCameraController() => MobileScannerController(
        formats: const [
          BarcodeFormat.ean13,
          BarcodeFormat.ean8,
          BarcodeFormat.upcA,
          BarcodeFormat.upcE,
          BarcodeFormat.code128,
        ],
        detectionSpeed: DetectionSpeed.normal,
      );

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  /// Req 27: the camera can die mid-session (permission revoked, another
  /// app grabs the camera, device too slow to initialize). Recreating the
  /// controller re-runs initialization — and re-requests permission —
  /// instead of leaving the shopkeeper trapped on a black screen.
  void _restartCamera() {
    final old = _cameraController;
    setState(() => _cameraController = _createCameraController());
    old.dispose();
  }

  /// Restart the live feed once a result sheet has closed.
  ///
  /// Skipped when the scanner is no longer the top route: a save or the
  /// conflict hand-off pops this screen, and `start()` on a controller that is
  /// being disposed throws `controllerDisposed` from an unawaited future.
  void _resumeScanning() {
    if (!mounted) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    setState(() => _isProcessing = false);
    unawaited(_startCameraSafely());
  }

  /// `MobileScannerController.start()` throws [MobileScannerException]
  /// (`controllerDisposed`) when the controller went away mid-call — expected
  /// while the screen is closing, and nothing is left to recover.
  ///
  /// It also refuses to start while the app is NOT resumed: a result sheet can
  /// close while the shopkeeper is in another app, and the camera must not be
  /// switched back on behind their back (§112 "do not leave camera active in
  /// background"). `mobile_scanner` re-enables the camera itself on resume
  /// (`useAppLifecycleState`), so skipping here is not a lost start.
  Future<void> _startCameraSafely() async {
    if (!_isForeground) return;
    try {
      await _cameraController.start();
    } on MobileScannerException {
      // The screen is gone; there is nothing left to restart.
    }
  }

  /// The mirror of [_startCameraSafely] for the detection path. `stop()` throws
  /// the same `controllerDisposed` exception when the screen closed between the
  /// frame callback and this call; left unhandled it surfaces as an uncaught
  /// async error in the zone rather than a no-op.
  Future<void> _stopCameraSafely() async {
    try {
      await _cameraController.stop();
    } on MobileScannerException {
      // Already gone — nothing to stop.
    }
  }

  /// True only while the app is in the foreground. A null lifecycle state (no
  /// binding yet, as in a unit test) is treated as foreground so the scanner
  /// still initialises outside a real app.
  bool get _isForeground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;
    if (capture.barcodes.isEmpty) return;
    final raw = capture.barcodes.first.rawValue;
    if (raw == null || raw.trim().isEmpty) return;

    setState(() => _isProcessing = true);
    unawaited(_stopCameraSafely());
    Future<void>(
        () => ref.read(barcodeControllerProvider.notifier).resolve(raw.trim()));
  }

  /// Renders the resolution result once the controller reaches `resolved`.
  void _handleResolved(BarcodeScanState state) {
    final resolution = state.resolution;
    if (resolution == null) return;

    final matches = resolution.matches;
    if (resolution.status == BarcodeResolutionStatus.found &&
        matches.isNotEmpty) {
      _showConfirmSheet(resolution, matches.first);
      return;
    }
    if (resolution.status == BarcodeResolutionStatus.multipleMatches &&
        matches.isNotEmpty) {
      _pickMatch(resolution);
      return;
    }

    // NOT_FOUND → dedicated "Product not found" sheet (req 27): echoes the
    // barcode, offers Try Again (resume camera) and Enter Manually (full
    // create form). No product-suggestion UI exists because the backend has
    // no suggestion endpoint — nothing is silently invented.
    if (resolution.status == BarcodeResolutionStatus.notFound) {
      showModalBottomSheet<void>(
        context: context,
        isDismissible: false,
        enableDrag: false,
        builder: (sheetContext) => BarcodeNotFoundSheet(
          barcode: resolution.barcode,
          onTryAgain: () {
            Navigator.of(sheetContext).pop();
            _resumeScanning();
          },
          onEnterManually: () {
            Navigator.of(sheetContext).pop();
            _showCreateProductSheet();
          },
        ),
      );
      return;
    }

    // INVALID / SERVICE_UNAVAILABLE → friendly message + manual retype.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_resultMessage(resolution)),
      action: SnackBarAction(
        label: 'Enter manually',
        onPressed: _showManualEntrySheet,
      ),
    ));
    _resumeScanning();
  }

  /// NOT_FOUND fallback (req 27): create the product via the full manual
  /// form; a successful create closes the scanner and refreshes inventory.
  void _showCreateProductSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ProductCreateSheet(
        onCreated: () {
          Navigator.of(context).pop(); // close the scanner screen
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Product added to inventory'),
          ));
          ref.read(productsControllerProvider.notifier).load();
        },
      ),
      // §112: this sheet is DISMISSIBLE, and the NOT_FOUND path that opens it
      // has already stopped the camera and latched `_isProcessing`. Without
      // this, dismissing the sheet without saving left a permanently dead
      // scanner — black preview, every later detection rejected by the latch.
      // On a successful create the scanner is popped, and `_resumeScanning`'s
      // mounted + isCurrent guards make this a no-op.
    ).whenComplete(_resumeScanning);
  }

  /// MULTIPLE_MATCHES: the shopkeeper must explicitly choose which catalog
  /// product they scanned (several masters share the same barcode).
  void _pickMatch(BarcodeResolution resolution) {
    showModalBottomSheet<CatalogProductMatch>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Multiple products share this barcode',
                  style: Theme.of(sheetContext).textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Please select the product you scanned:',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(sheetContext).colorScheme.outline,
                ),
              ),
            ),
            const SizedBox(height: 4),
            for (final match in resolution.matches)
              ListTile(
                leading: const Icon(Icons.qr_code_2_outlined),
                title: Text(match.name,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  match.isAvailableInCatalog
                      ? 'Available in catalog'
                      : 'Currently unavailable',
                  style: TextStyle(
                    fontSize: 12,
                    color: match.isAvailableInCatalog
                        ? Theme.of(sheetContext).colorScheme.primary
                        : Theme.of(sheetContext).colorScheme.error,
                  ),
                ),
                onTap: () => Navigator.of(sheetContext).pop(match),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ).then((match) {
      if (match != null && mounted) {
        _showConfirmSheet(resolution, match);
      } else {
        _resumeScanning();
      }
    });
  }

  String _resultMessage(BarcodeResolution resolution) =>
      switch (resolution.status) {
        BarcodeResolutionStatus.notFound =>
          'No catalog product found for ${resolution.barcode}',
        BarcodeResolutionStatus.invalid => 'Invalid barcode format',
        BarcodeResolutionStatus.serviceUnavailable =>
          'Barcode lookup is temporarily unavailable — please retry',
        _ => resolution.message ?? 'Could not resolve barcode',
      };

  void _showConfirmSheet(
      BarcodeResolution resolution, CatalogProductMatch match) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => BarcodeConfirmSheet(
        resolution: resolution,
        selectedMatch: match,
        onSaved: () {
          Navigator.of(context)
            ..pop() // close sheet
            ..pop(); // close scanner screen
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Product added to inventory'),
          ));
          // Refresh inventory so the new product is visible.
          ref.read(productsControllerProvider.notifier).load();
        },
      ),
    ).whenComplete(_resumeScanning);
  }

  void _showManualEntrySheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const BarcodeManualEntrySheet(),
    ).whenComplete(_resumeScanning);
  }

  @override
  Widget build(BuildContext context) {
    // React to scan-state transitions (never inside build).
    ref.listen<BarcodeScanState>(barcodeControllerProvider, (prev, next) {
      if (next.status == BarcodeScanStatus.resolved &&
          prev?.status != BarcodeScanStatus.resolved) {
        _handleResolved(next);
      } else if (next.status == BarcodeScanStatus.error &&
          prev?.status != BarcodeScanStatus.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.message ?? 'Something went wrong')),
        );
        _resumeScanning();
      }
    });

    final status =
        ref.watch(barcodeControllerProvider.select((s) => s.status));
    // The busy indicator belongs to THIS scanning session, so it is driven by
    // this screen's own [_isProcessing] latch (set the moment a code is
    // detected, cleared when a result sheet closes) plus a save in flight.
    // Deriving it from the inherited `resolving` status instead would let a
    // previous session — the container-scoped controller outlives this screen —
    // park a permanent spinner over a camera that is working fine (§112).
    final showProgress = _isProcessing || status == BarcodeScanStatus.saving;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan barcode'),
        actions: [
          if (showProgress)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.keyboard_alt_outlined),
              tooltip: 'Enter barcode manually',
              onPressed: _showManualEntrySheet,
            ),
        ],
      ),
      // The camera-permission conversation (explain → request → denied →
      // system-settings guidance) lives in the gate, so MobileScanner is never
      // built — and never asks for the camera itself — before the grant.
      body: BarcodeCameraGate(
        onEnterManually: _showManualEntrySheet,
        cameraBuilder: _cameraPreview,
      ),
    );
  }

  /// The live camera preview + scan-frame overlay, built by [BarcodeCameraGate]
  /// once the camera permission has been granted.
  Widget _cameraPreview(BuildContext context) =>
      ValueListenableBuilder<MobileScannerState>(
        valueListenable: _cameraController,
        builder: (context, cameraState, _) {
          // Req 27: the frame and its instruction only make sense over a live
          // camera. When initialization fails (permission denied, unsupported
          // device, camera taken by another app) MobileScanner renders the
          // error view, and this overlay used to be drawn on top of it —
          // hiding the message that explains what went wrong.
          final cameraFailed = cameraState.error != null;
          return Stack(
            children: [
              MobileScanner(
                controller: _cameraController,
                onDetect: _onDetect,
                // Req 27: explicit permission-denied / unavailable states —
                // Retry re-initializes the camera; manual entry and the AppBar
                // back button are always available so the user is never
                // trapped.
                errorBuilder: (context, error) => _ScannerErrorView(
                  error: error,
                  onRetry: _restartCamera,
                  onManualEntry: _showManualEntrySheet,
                  onOpenSettings: _openSystemSettings,
                ),
              ),
              if (!cameraFailed) ...[
                // Scan-frame overlay.
                Center(
                  child: Container(
                    width: 260,
                    height: 260,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 3,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'Position a product barcode inside the frame — '
                        'it is detected automatically.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      );

  /// The way back from a permission that was revoked while the app was open or
  /// blocked after the grant (runtime failure path of the scanner).
  Future<void> _openSystemSettings() =>
      ref.read(permissionServiceProvider).openSystemSettings();
}

/// Req 27: dedicated camera-failure view. Distinguishes permission denial
/// (fix in system Settings, then retry) from unsupported devices and other
/// initialization failures. Manual barcode entry is always offered so the
/// flow never dead-ends; back navigation stays in the AppBar.
///
/// A permission denial found HERE (rather than by the gate) means the grant
/// disappeared at runtime, so the view also offers the system-settings escape
/// hatch next to Retry.
class _ScannerErrorView extends StatelessWidget {
  const _ScannerErrorView({
    required this.error,
    required this.onRetry,
    required this.onManualEntry,
    required this.onOpenSettings,
  });

  final MobileScannerException? error;
  final VoidCallback onRetry;
  final VoidCallback onManualEntry;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final code = error?.errorCode;
    final (IconData icon, String title, String detail) = switch (code) {
      MobileScannerErrorCode.permissionDenied => (
          Icons.no_photography_outlined,
          'Camera permission needed',
          'Enable the camera for this app in system Settings, then retry. '
              'You can also add products without scanning.',
        ),
      MobileScannerErrorCode.unsupported => (
          Icons.videocam_off_outlined,
          'Camera unavailable',
          'Barcode scanning is not supported on this device. '
              'Enter the barcode manually instead.',
        ),
      _ => (
          Icons.error_outline,
          'Camera unavailable',
          'The camera could not start. Retry, or enter the barcode '
              'manually.',
        ),
    };

    return Container(
      width: double.infinity,
      color: AppColors.overlayBackdrop,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(icon, color: AppColors.onOverlay, size: 48),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.onOverlay,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.onOverlayMuted, fontSize: 13),
          ),
          const SizedBox(height: 24),
          // Retry is pointless when the device simply cannot scan.
          if (code != MobileScannerErrorCode.unsupported)
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry camera'),
            ),
          const SizedBox(height: 12),
          // A runtime permission loss can only be fixed in the system
          // settings, so that escape hatch sits right under Retry.
          if (code == MobileScannerErrorCode.permissionDenied) ...[
            OutlinedButton.icon(
              key: const Key('scanner_open_settings'),
              onPressed: onOpenSettings,
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Open System Settings'),
            ),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(
            onPressed: onManualEntry,
            icon: const Icon(Icons.keyboard_alt_outlined),
            label: const Text('Enter barcode manually'),
          ),
        ],
      ),
    );
  }
}


