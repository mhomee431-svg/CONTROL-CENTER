import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../products/presentation/controllers/products_controller.dart';
import 'domain/barcode_models.dart';
import 'presentation/controllers/barcode_controller.dart';
import 'presentation/widgets/barcode_sheets.dart';

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
  late final MobileScannerController _cameraController;

  /// Guards against duplicate detections of the same code while a resolve
  /// round-trip is in flight.
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _cameraController = MobileScannerController(
      formats: const [
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
        BarcodeFormat.code128,
      ],
      detectionSpeed: DetectionSpeed.normal,
    );
  }

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  void _resumeScanning() {
    if (!mounted) return;
    setState(() => _isProcessing = false);
    _cameraController.start();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;
    if (capture.barcodes.isEmpty) return;
    final raw = capture.barcodes.first.rawValue;
    if (raw == null || raw.trim().isEmpty) return;

    setState(() => _isProcessing = true);
    _cameraController.stop();
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

    // NOT_FOUND / INVALID / SERVICE_UNAVAILABLE → friendly message + retry.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_resultMessage(resolution)),
      action: SnackBarAction(
        label: 'Enter manually',
        onPressed: _showManualEntrySheet,
      ),
    ));
    _resumeScanning();
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
    final showProgress = status == BarcodeScanStatus.resolving ||
        status == BarcodeScanStatus.saving;

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
      body: Stack(
        children: [
          MobileScanner(controller: _cameraController, onDetect: _onDetect),
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
      ),
    );
  }
}

