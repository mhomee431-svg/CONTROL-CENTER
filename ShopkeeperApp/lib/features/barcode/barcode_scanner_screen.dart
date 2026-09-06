import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Barcode scanner screen for shopkeeper inventory management.
///
/// Features:
/// - Camera-based barcode scanning
/// - Manual barcode entry
/// - Product lookup by barcode
/// - Quick product add flow
class BarcodeScannerScreen extends ConsumerStatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  ConsumerState<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends ConsumerState<BarcodeScannerScreen> {
  final TextEditingController _barcodeController = TextEditingController();
  bool _isScanning = false;
  String? _scannedBarcode;
  Map<String, dynamic>? _product;

  @override
  void dispose() {
    _barcodeController.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() => _isScanning = true);

    // In a real implementation, this would use a barcode scanner plugin
    // like 'mobile_scanner' or 'qr_code_scanner'
    // For now, we show a placeholder
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Scan Barcode'),
        content: const Text(
          'Camera barcode scanning requires the mobile_scanner plugin.\n\n'
          'For now, please enter the barcode manually.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    setState(() => _isScanning = false);
  }

  Future<void> _lookupBarcode() async {
    final barcode = _barcodeController.text.trim();
    if (barcode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a barcode')),
      );
      return;
    }

    setState(() => _scannedBarcode = barcode);

    // TODO: Call backend API to lookup product by barcode
    // final product = await ref.read(barcodeRepositoryProvider).lookup(barcode);

    // Placeholder
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Looking up barcode: $barcode')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Barcode'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Manual barcode entry
            TextField(
              controller: _barcodeController,
              decoration: const InputDecoration(
                labelText: 'Barcode',
                hintText: 'Enter barcode manually',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.qr_code),
              ),
              keyboardType: TextInputType.number,
              onSubmitted: (_) => _lookupBarcode(),
            ),
            const SizedBox(height: 16),

            // Scan button
            ElevatedButton.icon(
              onPressed: _isScanning ? null : _startScan,
              icon: _isScanning
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.camera_alt),
              label: Text(_isScanning ? 'Scanning...' : 'Scan with Camera'),
            ),
            const SizedBox(height: 24),

            // Lookup button
            FilledButton(
              onPressed: _lookupBarcode,
              child: const Text('Lookup Product'),
            ),
            const SizedBox(height: 24),

            // Scan result
            if (_scannedBarcode != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Scanned: $_scannedBarcode',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      if (_product != null) ...[
                        Text('Name: ${_product!['name']}'),
                        Text('Price: ₹${_product!['price']}'),
                      ] else
                        const Text('Product not found'),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}