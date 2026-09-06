import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Excel import screen for bulk inventory management.
class ExcelImportScreen extends ConsumerStatefulWidget {
  final String shopId;

  const ExcelImportScreen({super.key, required this.shopId});

  @override
  ConsumerState<ExcelImportScreen> createState() => _ExcelImportScreenState();
}

class _ExcelImportScreenState extends ConsumerState<ExcelImportScreen> {
  bool _isImporting = false;
  double _progress = 0;
  String? _selectedFile;
  Map<String, dynamic>? _importResult;

  Future<void> _pickFile() async {
    setState(() => _selectedFile = 'inventory_sample.xlsx');
  }

  Future<void> _downloadTemplate() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Downloading template...')),
    );
  }

  Future<void> _startImport() async {
    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a file first')),
      );
      return;
    }

    setState(() {
      _isImporting = true;
      _progress = 0;
    });

    for (var i = 0; i <= 100; i += 10) {
      await Future.delayed(const Duration(milliseconds: 200));
      setState(() => _progress = i / 100);
    }

    setState(() {
      _isImporting = false;
      _importResult = {
        'total': 150,
        'success': 142,
        'failed': 8,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import Inventory')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Import Instructions', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    const Text('1. Download the template'),
                    const Text('2. Fill in your product data'),
                    const Text('3. Upload the completed file'),
                    TextButton.icon(
                      onPressed: _downloadTemplate,
                      icon: const Icon(Icons.download),
                      label: const Text('Download Template'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _isImporting ? null : _pickFile,
              icon: const Icon(Icons.upload_file),
              label: Text(_selectedFile ?? 'Select Excel File'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _isImporting || _selectedFile == null ? null : _startImport,
              child: _isImporting
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 12),
                        Text('Importing...'),
                      ],
                    )
                  : const Text('Start Import'),
            ),
            const SizedBox(height: 16),
            if (_isImporting) ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text('${(_progress * 100).toInt()}% complete'),
            ],
            if (_importResult != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Import Results', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text('Total rows: ${_importResult!['total']}'),
                      Text('Successful: ${_importResult!['success']}'),
                      Text('Failed: ${_importResult!['failed']}'),
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