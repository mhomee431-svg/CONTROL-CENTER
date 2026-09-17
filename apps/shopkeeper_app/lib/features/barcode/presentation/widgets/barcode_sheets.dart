import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/barcode_repository.dart';
import '../../domain/barcode_models.dart';
import '../controllers/barcode_controller.dart';

/// Bottom sheet shown after a successful barcode resolution.
///
/// Single shopkeeper-facing contract: confirm the catalog product, pick a
/// variant (optional), enter price / MRP / quantity → save to inventory.
/// Validation is client-side (mirrors the backend BarcodeSaveRequest rules)
/// and double-submit safe.
class BarcodeConfirmSheet extends ConsumerStatefulWidget {
  const BarcodeConfirmSheet({
    super.key,
    required this.resolution,
    required this.selectedMatch,
    required this.onSaved,
  });

  /// Full resolution result (used for MULTIPLE_MATCHES disambiguation).
  final BarcodeResolution resolution;

  /// The match the user is confirming (first match for FOUND, chosen one
  /// for MULTIPLE_MATCHES).
  final CatalogProductMatch selectedMatch;

  /// Called after a successful save — the screen pops and refreshes
  /// the inventory list.
  final VoidCallback onSaved;

  @override
  ConsumerState<BarcodeConfirmSheet> createState() =>
      _BarcodeConfirmSheetState();
}

class _BarcodeConfirmSheetState extends ConsumerState<BarcodeConfirmSheet> {
  final _formKey = GlobalKey<FormState>();
  final _price = TextEditingController();
  final _mrp = TextEditingController();
  final _quantity = TextEditingController(text: '0');
  ProductVariant? _variant;
  bool _publish = true;
  bool _saving = false;

  @override
  void dispose() {
    _price.dispose();
    _mrp.dispose();
    _quantity.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return; // double-submit guard
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final price = double.tryParse(_price.text.trim()) ?? 0;
    final mrp = double.tryParse(_mrp.text.trim());
    if (mrp != null && mrp < price) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('MRP cannot be lower than the selling price'),
      ));
      return;
    }

    try {
      final created = await ref
          .read(barcodeControllerProvider.notifier)
          .saveFromScan(BarcodeSavePayload(
            barcode: widget.resolution.barcode,
            productMasterId: widget.selectedMatch.productMasterId,
            variantId: _variant?.id,
            price: price,
            mrp: mrp,
            quantity: int.tryParse(_quantity.text.trim()) ?? 0,
            publish: _publish,
          ));
      if (!mounted) return;
      if (created != null) {
        // Never leave the button mid-save: the caller pops this sheet, but the
        // spinner must not outlive the save if it does not.
        setState(() => _saving = false);
        widget.onSaved();
        return;
      }
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save the product')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      if (e.statusCode == 409) {
        // Req 27: the scanned product is already in this shop's inventory.
        // Offer a way out instead of a dead-end error.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('This product is already in your inventory'),
          action: SnackBarAction(
            label: 'View products',
            onPressed: () {
              Navigator.of(context)
                ..pop() // close the confirm sheet
                ..pop(); // close the scanner screen
              // Req 27: the scanner is launched from the Products tab and from
              // the dashboard's Add Product action, so `push` here stacked a
              // second Products page on top of the one already open. `go`
              // reselects the tab instead — the same call the Alerts deep-link
              // uses for this destination.
              context.go(Routes.products);
            },
          ),
        ));
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save the product')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final match = widget.selectedMatch;
    final isAvailableInCatalog = match.isAvailableInCatalog;
    final theme = Theme.of(context);

        return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              // Product image (when the catalog master has one). The
              // errorBuilder keeps the sheet usable when the (short-lived)
              // image URL has expired or the network is unavailable.
              if (match.imageUrl != null && match.imageUrl!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: CircleAvatar(
                    radius: 22,
                    child: ClipOval(
                      child: Image.network(
                        match.imageUrl!,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        // Decode at ~2x the 44px avatar instead of the source
                        // resolution: a thumbnail never needs the full bytes.
                        cacheWidth: 88,
                        errorBuilder: (_, e, stack) =>
                            const Icon(Icons.image_outlined, size: 20),
                      ),
                    ),
                  ),
                ),
              // Name + brand.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      match.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    if (match.brand != null && match.brand!.isNotEmpty)
                      Text(
                        match.brand!,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ]),
            Text(
              'Barcode ${widget.resolution.barcode}'
              '${widget.resolution.barcodeType != null ? ' · ${widget.resolution.barcodeType}' : ''}',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 4),
            Row(children: [
              Icon(
                isAvailableInCatalog
                    ? Icons.check_circle_outline
                    : Icons.block_outlined,
                size: 16,
                color: isAvailableInCatalog
                    ? AppTheme.verifiedGreen
                    : theme.colorScheme.error,
              ),
              const SizedBox(width: 6),
              Text(
                isAvailableInCatalog
                    ? 'Available in catalog'
                    : 'Currently unavailable in catalog',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isAvailableInCatalog
                      ? AppTheme.verifiedGreen
                      : theme.colorScheme.error,
                ),
              ),
            ]),
            if (!isAvailableInCatalog) ...[
              const SizedBox(height: 12),
              Text(
                'This product is not currently published in the shared catalog. '
                'You cannot list it right now.',
                style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
              ),
            ],
            if (match.variants.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<ProductVariant>(
                initialValue: _variant,
                decoration:
                    const InputDecoration(labelText: 'Variant (optional)'),
                items: [
                  for (final v in match.variants)
                    DropdownMenuItem(value: v, child: Text(v.name)),
                ],
                onChanged: (v) => setState(() => _variant = v),
              ),
            ],
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _price,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Selling price *', prefixText: '₹ '),
                  validator: (v) {
                    final value = double.tryParse((v ?? '').trim());
                    if (value == null) return 'Required';
                    if (value < 0) return 'Cannot be negative';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _mrp,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'MRP (optional)', prefixText: '₹ '),
                  validator: (v) {
                    final value = double.tryParse((v ?? '').trim());
                    if (value != null && value < 0) return 'Cannot be negative';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _quantity,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Quantity'),
                  validator: (v) {
                    final value = int.tryParse((v ?? '').trim());
                    if (value == null || value < 0) return '≥ 0';
                    return null;
                  },
                ),
              ),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Publish immediately'),
              subtitle: const Text('Unpublished products stay as drafts'),
              value: _publish,
              onChanged: (v) => setState(() => _publish = v),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: (!isAvailableInCatalog || _saving) ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add),
              label: const Text('Add to inventory'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Manual barcode entry — used when the camera fails, the code is damaged,
/// or the resolution result is NOT_FOUND (retyped to correct an OCR error).
class BarcodeManualEntrySheet extends ConsumerStatefulWidget {
  const BarcodeManualEntrySheet({super.key});

  @override
  ConsumerState<BarcodeManualEntrySheet> createState() =>
      _BarcodeManualEntrySheetState();
}

class _BarcodeManualEntrySheetState
    extends ConsumerState<BarcodeManualEntrySheet> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _resolving = false;

  // The same barcode families the camera accepts and the backend validates
  // (`VALID_BARCODE_LENGTHS`): EAN-8 (8), UPC-A (12), EAN-13 (13) and
  // GTIN-14 (14) digits. EAN-13 was missing from the old pattern, so the
  // most common retail barcode in India was rejected by this form.
  static final _barcodePattern = RegExp(r'^(?:\d{8}|\d{12,14})$');

  /// Mirrors the backend's `normalize_barcode`: separators printed around a
  /// barcode are stripped before the digits are validated.
  static String _normalize(String raw) =>
      raw.trim().replaceAll(RegExp(r'[\s-]'), '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_resolving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _resolving = true);
    Navigator.pop(context); // dismiss the sheet; the screen shows progress
    await ref
        .read(barcodeControllerProvider.notifier)
        .resolve(_normalize(_controller.text));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Enter barcode',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'EAN-8, UPC-A, EAN-13 or GTIN-14 — digits only.',
              style: TextStyle(
                  fontSize: 12, color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 20, // 14 digits + the separators _normalize strips
              decoration: const InputDecoration(
                labelText: 'Barcode',
                hintText: 'e.g. 8901234567890',
                counterText: '',
              ),
              validator: (v) {
                final value = _normalize(v ?? '');
                if (value.isEmpty) return 'Barcode is required';
                if (!_barcodePattern.hasMatch(value)) {
                  return 'Enter 8, 12, 13 or 14 digits';
                }
                return null;
              },
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _resolving ? null : _submit,
              icon: _resolving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.search),
              label: const Text('Look up'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when a scanned barcode resolves to NOT_FOUND (req 27).
///
/// Contract:
///   * Explicitly says "Product not found" — never invents a Product Master
///     or fabricates a match the backend did not return.
///   * Offers exactly two actions: [Try Again] (rescan) and
///     [Enter Manually] (open the manual entry form so the shopkeeper can
///     add the listing themselves). No Product Master is ever invented on
///     the shopkeeper's behalf.
///   * Product suggestion / "request this product" is only ever shown when a
///     backend endpoint for it exists. No such endpoint exists today, so this
///     sheet intentionally renders no suggestion UI.
class BarcodeNotFoundSheet extends StatelessWidget {
  const BarcodeNotFoundSheet({
    super.key,
    required this.barcode,
    required this.onTryAgain,
    required this.onEnterManually,
  });

  /// The barcode that could not be matched, echoed back so the shopkeeper can
  /// verify the digits (a mis-scan is the most common cause).
  final String barcode;

  /// Resume the camera for another scan attempt.
  final VoidCallback onTryAgain;

  /// Open the manual product-entry form.
  final VoidCallback onEnterManually;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.search_off_outlined,
                size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              'Product not found',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'No catalog product matches barcode '
              '$barcode.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Check the barcode digits, or add the item manually — it will '
              'be created under your shop.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onTryAgain,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onEnterManually,
              icon: const Icon(Icons.keyboard_alt_outlined),
              label: const Text('Enter Manually'),
            ),
          ],
        ),
      ),
    );
  }
}

