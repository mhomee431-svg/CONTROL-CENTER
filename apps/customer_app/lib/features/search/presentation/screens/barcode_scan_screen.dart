import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../core/permissions/data/permission_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/empty_state_view.dart';
import '../../domain/barcode_validation.dart';
import '../widgets/barcode_camera_gate.dart';
import '../widgets/barcode_lookup_sheet.dart';
import '../widgets/barcode_scan_results_view.dart';

/// Builds the live-camera subtree and reports every detected barcode.
///
/// WHY A SEAM: `MobileScanner` needs a real camera and a real platform plugin,
/// so without this the whole scan flow — detect → look up → results → scan
/// another — would be untestable. Tests inject a widget that calls
/// `onDetection('8901234567890')` from a button and drive the real screen.
typedef BarcodeLiveScannerBuilder = Widget Function(
  BuildContext context,
  ValueChanged<String> onDetection,
);

/// Full-screen camera barcode scanner for customers.
///
/// Flow:
///   1. The permission gate reads the camera status (never starts the camera
///      before the grant) and, on first use, explains why it is asking.
///   2. The first barcode inside the frame is captured, the camera stops, and
///      the code goes straight to `GET /search/v2/barcodes/{barcode}`.
///   3. The answer replaces the viewfinder in place — the same cards, the same
///      disclaimer, the same product/shop routes as a typed search.
///   4. "Scan another barcode" returns to a live viewfinder.
///
/// Manual entry is reachable from the AppBar in every state and is the only
/// option the scanner offers when the camera cannot be used at all, so a
/// customer without a working camera is never locked out of barcode search.
class BarcodeScanScreen extends ConsumerStatefulWidget {
  const BarcodeScanScreen({super.key, this.scannerBuilder});

  /// Test/preview replacement for the live camera. Defaults to `mobile_scanner`.
  final BarcodeLiveScannerBuilder? scannerBuilder;

  @override
  ConsumerState<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

class _BarcodeScanScreenState extends ConsumerState<BarcodeScanScreen> {
  /// The camera controller is created lazily, ONLY when a live viewfinder is
  /// actually rendered: constructing one when the permission gate is still
  /// showing its explanation (or when a test replaced the camera) would touch
  /// platform channels that may not exist.
  MobileScannerController? _camera;

  /// The frozen code whose results are on screen. Non-null means the results
  /// view replaced the viewfinder.
  String? _scannedBarcode;

  /// A detected code that failed client-side validation. Shown as a dedicated
  /// notice — NOT as a lookup error — because no network call was made and the
  /// fix is "hold still and re-scan", not "retry the request".
  ({String code, BarcodeInvalidReason reason})? _invalidBarcode;

  MobileScannerController _createCameraController() => MobileScannerController(
        // Retail formats only: accepting every symbology (QR, PDF417, data
        // matrix…) makes a shop floor scan pick up a QR sticker on a nearby
        // box and look up a nonsense "barcode".
        formats: const [
          BarcodeFormat.ean13,
          BarcodeFormat.ean8,
          BarcodeFormat.upcA,
          BarcodeFormat.upcE,
          BarcodeFormat.code128,
        ],
        detectionSpeed: DetectionSpeed.normal,
      );

  MobileScannerController _ensureCamera() =>
      _camera ??= _createCameraController();

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  /// The camera can die mid-session (permission revoked while the app was
  /// open, another app took the lens, the device was too slow to initialize).
  /// Dropping the controller makes the next build re-initialize it — and
  /// re-request the permission — instead of leaving the customer on a black
  /// screen.
  void _restartCamera() {
    final old = _camera;
    setState(() {
      _camera = null;
      _scannedBarcode = null;
      _invalidBarcode = null;
    });
    old?.dispose();
  }

  /// `start()`/`stop()` throw `MobileScannerException` (`controllerDisposed`)
  /// when the controller goes away mid-call — expected while this screen is
  /// closing, and there is nothing left to recover.
  Future<void> _startCameraSafely() async {
    try {
      await _camera?.start();
    } on MobileScannerException {
      // The camera is gone; the next build creates a fresh one.
    }
  }

  Future<void> _stopCameraSafely() async {
    try {
      await _camera?.stop();
    } on MobileScannerException {
      // Same: the screen or the camera went away first.
    }
  }

  /// Restart the live feed once a sheet has closed.
  ///
  /// Skipped when this screen is no longer the top route: pushing a product
  /// detail page leaves the camera paused underneath on purpose, and `start()`
  /// on a controller that is being torn down throws from an unawaited future.
  Future<void> _resumeAfterSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const BarcodeLookupSheet(),
    );
    if (!mounted) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    if (_scannedBarcode != null) return;
    await _startCameraSafely();
  }

  void _openManualEntry() => _resumeAfterSheet();

  /// Freezes the FIRST readable code. `DetectionSpeed.normal` keeps reporting,
  /// and a second hit while the lookup is in flight would fire a second request
  /// for the same product.
  ///
  /// Validation runs BEFORE anything is frozen: a partial read (too short, bad
  /// check digit) is overwhelmingly a camera-angle problem, so it lands on the
  /// invalid notice — with the digits echoed back — instead of burning a lookup
  /// that can only fail.
  void _onDetected(String raw) {
    final code = normalizeBarcode(raw);
    if (code.isEmpty) return;
    if (_scannedBarcode != null || _invalidBarcode != null) return;
    // Physical confirmation that the code is locked in — the customer can put
    // the phone down without watching for a tick that is easy to miss.
    unawaited(HapticFeedback.vibrate());
    final reason = validateBarcode(code);
    if (reason != null) {
      setState(() => _invalidBarcode = (code: code, reason: reason));
      unawaited(_stopCameraSafely());
      return;
    }
    setState(() => _scannedBarcode = code);
    unawaited(_stopCameraSafely());
  }

  void _onCapture(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.trim().isNotEmpty) {
        _onDetected(raw);
        return;
      }
    }
  }

  void _scanAnother() {
    setState(() {
      _scannedBarcode = null;
      _invalidBarcode = null;
    });
    unawaited(_startCameraSafely());
  }

  Future<void> _openSystemSettings() =>
      ref.read(permissionServiceProvider).openSystemSettings();

  @override
  Widget build(BuildContext context) {
    final scanned = _scannedBarcode;
    final invalid = _invalidBarcode;
    final showingResults = scanned != null || invalid != null;
    return Scaffold(
      backgroundColor: showingResults ? null : Colors.black,
      appBar: AppBar(
        backgroundColor: showingResults ? null : Colors.black,
        foregroundColor: showingResults ? null : Colors.white,
        title: Text(
          scanned != null
              ? 'Scan results'
              : invalid != null
                  ? 'Check the barcode'
                  : 'Scan barcode',
        ),
        actions: [
          IconButton(
            key: const Key('scan_manual_entry'),
            icon: const Icon(Icons.keyboard_alt_outlined),
            tooltip: 'Enter barcode manually',
            onPressed: _openManualEntry,
          ),
        ],
      ),
      // The permission conversation (explain → request → denied → system
      // settings) lives in the gate, so MobileScanner is never built — and
      // never asks for the camera itself — before the grant.
      body: invalid != null
          ? _InvalidBarcodeNotice(
              code: invalid.code,
              reason: invalid.reason,
              onScanAnother: _scanAnother,
              onEnterManually: _openManualEntry,
            )
          : scanned == null
              ? BarcodeCameraGate(
                  cameraBuilder: _liveCamera,
                  onEnterManually: _openManualEntry,
                )
              : BarcodeScanResultsView(
                  barcode: scanned,
                  onScanAnother: _scanAnother,
                  onEnterManually: _openManualEntry,
                ),
    );
  }

  /// The viewfinder + framing overlay, built by the gate only after the grant.
  Widget _liveCamera(BuildContext context) {
    final override = widget.scannerBuilder;
    if (override != null) return override(context, _onDetected);

    final controller = _ensureCamera();
    return ValueListenableBuilder<MobileScannerState>(
      valueListenable: controller,
      builder: (context, cameraState, _) {
        // The frame and its instruction only make sense over a live image.
        // When initialization fails, MobileScanner renders its error view, and
        // this overlay must not be drawn on top of the message that explains
        // what went wrong.
        final cameraFailed = cameraState.error != null;
        return Stack(
          children: [
            Positioned.fill(
              child: MobileScanner(
                controller: controller,
                onDetect: _onCapture,
                errorBuilder: (context, error) => _ScannerFailureView(
                  error: error,
                  onRetry: _restartCamera,
                  onManualEntry: _openManualEntry,
                  onOpenSettings: _openSystemSettings,
                ),
              ),
            ),
            if (!cameraFailed) ...[
              const Center(
                child: SizedBox(
                  width: 250,
                  height: 160,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.fromBorderSide(
                        BorderSide(color: Colors.white, width: 3),
                      ),
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                    ),
                  ),
                ),
              ),
              const Positioned(
                left: 24,
                right: 24,
                bottom: 48,
                child: Text(
                  'Hold a product barcode inside the frame — it is read '
                  'automatically.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(blurRadius: 8, color: Colors.black)],
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// A scan that never reached the network: the digits are not shaped like a
/// product barcode.
///
/// Shown as its own notice — not a lookup error — because "retry the request"
/// is the wrong action; NOTHING was requested. Echoes the captured digits (a
/// misread usually shows one or two wrong/wobbly digits) and offers re-scan
/// plus manual entry, which bypasses validation-free scanning entirely.
class _InvalidBarcodeNotice extends StatelessWidget {
  const _InvalidBarcodeNotice({
    required this.code,
    required this.reason,
    required this.onScanAnother,
    required this.onEnterManually,
  });

  final String code;
  final BarcodeInvalidReason reason;
  final VoidCallback onScanAnother;
  final VoidCallback onEnterManually;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: EmptyStateView(
            key: const Key('barcode_invalid_notice'),
            icon: Icons.barcode_reader,
            title: 'That does not look like a barcode',
            message: '${invalidBarcodeMessage(reason)}\n\nRead: $code',
            actionLabel: 'Scan again',
            actionIcon: Icons.qr_code_scanner,
            onActionTap: onScanAnother,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xl,
            right: AppSpacing.xl,
            bottom: AppSpacing.lg,
          ),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onEnterManually,
              icon: const Icon(Icons.keyboard_alt_outlined),
              label: const Text('Enter barcode manually'),
            ),
          ),
        ),
      ],
    );
  }
}

/// Camera-failure view rendered by `MobileScanner.errorBuilder`.
///
/// Distinguishes a permission lost at runtime (fixable in system Settings)
/// from a device that cannot scan at all, because the ways forward differ.
/// Manual entry is always offered — a customer whose camera broke mid-session
/// still has the same answer available, only one tap further away.
class _ScannerFailureView extends StatelessWidget {
  const _ScannerFailureView({
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
          'Enable the camera for this app in system Settings, then retry. You '
              'can also type the barcode instead.',
        ),
      MobileScannerErrorCode.unsupported => (
          Icons.videocam_off_outlined,
          'Camera unavailable',
          'Barcode scanning is not supported on this device. Type the barcode '
              'instead.',
        ),
      _ => (
          Icons.error_outline,
          'Camera unavailable',
          'The camera could not start. Retry, or type the barcode instead.',
        ),
    };

    return ColoredBox(
      color: Colors.black87,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(icon, color: Colors.white, size: 48),
              const SizedBox(height: AppSpacing.md),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: AppSpacing.lg),
              // Retry cannot help when the device simply cannot scan.
              if (code != MobileScannerErrorCode.unsupported)
                FilledButton.icon(
                  key: const Key('scanner_retry'),
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry camera'),
                ),
              if (code == MobileScannerErrorCode.permissionDenied) ...[
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  key: const Key('scanner_open_settings'),
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Open System Settings'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                key: const Key('scanner_manual_entry'),
                onPressed: onManualEntry,
                icon: const Icon(Icons.keyboard_alt_outlined),
                label: const Text('Enter barcode manually'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


