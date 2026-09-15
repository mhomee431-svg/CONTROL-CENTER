import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/media_upload_service.dart';
import '../../../../core/network/token_store.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../domain/product_models.dart';
import '../controllers/products_controller.dart';

/// Shared product-image picker + uploader (used by the create and edit
/// sheets). Client-side pre-flight mirrors the backend rules for a fast,
/// friendly failure before any network round trip.
///
/// Returns the confirmed [MediaObject] + local file path for preview, or
/// null when the user cancelled — a failed upload is non-fatal: product
/// images are optional, so callers keep the form usable either way.
Future<(MediaObject, String)?> _pickAndUploadProductImage(
  BuildContext context,
  WidgetRef ref, {
  required void Function(bool uploading) onUploading,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  void showMessage(String message) =>
      messenger.showSnackBar(SnackBar(content: Text(message)));

  final picked = await FilePicker.platform.pickFiles(
    type: FileType.image,
    withData: false,
  );
  final path = picked?.files.single.path;
  if (path == null) return null; // user cancelled (or no local path)
  if (!context.mounted) return null;

  final ext = path.contains('.') ? path.split('.').last.toLowerCase() : '';
  final contentType = switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => '',
  };
  if (contentType.isEmpty) {
    showMessage('Only JPG, PNG or WebP images are supported');
    return null;
  }
  final size = File(path).lengthSync();
  if (size > MediaUploadService.maxImageBytes) {
    showMessage('Image must be smaller than 5 MB');
    return null;
  }

  onUploading(true);
  try {
    final token = await ref.read(tokenStoreProvider).readAccessToken();
    if (token == null) throw const ApiException(message: 'Not signed in');
    final media = await ref.read(mediaUploadServiceProvider).upload(
          token: token,
          category: 'PRODUCT_IMAGE',
          filePath: path,
          contentType: contentType,
          shopId: ref.read(selectedShopProvider)?.id,
        );
    return (media, path);
  } on ApiException catch (e) {
    showMessage(e.message);
    return null;
  } catch (_) {
    showMessage('Image upload failed — you can still save the product');
    return null;
  } finally {
    onUploading(false);
  }
}

/// Bottom sheet to edit price / MRP / stock for an existing shop product.
class ProductEditSheet extends ConsumerStatefulWidget {
  const ProductEditSheet({super.key, required this.item});

  final ShopProductItem item;

  @override
  ConsumerState<ProductEditSheet> createState() => _ProductEditSheetState();
}

class _ProductEditSheetState extends ConsumerState<ProductEditSheet> {
  late final TextEditingController _price =
      TextEditingController(text: widget.item.price.toStringAsFixed(2));
  late final TextEditingController _mrp = TextEditingController(
      text: widget.item.mrp?.toStringAsFixed(2) ?? '');
  late final TextEditingController _quantity =
      TextEditingController(text: '${widget.item.quantity}');
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  /// Newly picked replacement image (sent as `image_key` on save).
  MediaObject? _image;
  String? _imagePath;
  bool _uploadingImage = false;

  @override
  void dispose() {
    _price.dispose();
    _mrp.dispose();
    _quantity.dispose();
    super.dispose();
  }

  /// Pick + upload a replacement product photo via the shared helper.
  /// Upload failure is non-fatal — the shopkeeper can save without it.
  Future<void> _pickImage() async {
    if (_uploadingImage) return;
    final result = await _pickAndUploadProductImage(
      context,
      ref,
      onUploading: (uploading) {
        if (mounted) setState(() => _uploadingImage = uploading);
      },
    );
    if (result == null || !mounted) return;
    setState(() {
      _image = result.$1;
      _imagePath = result.$2;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final ok = await ref.read(productsControllerProvider.notifier).saveEdits(
          productId: widget.item.id,
          price: double.tryParse(_price.text.trim()),
          mrp: double.tryParse(_mrp.text.trim()),
          quantity: int.tryParse(_quantity.text.trim()),
          imageKey: _image?.key,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Product updated' : 'Update failed'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
              Expanded(
                child: Text('Edit ${widget.item.name}',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close)),
            ]),
            const SizedBox(height: 8),
            TextFormField(
              controller: _price,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Selling price'),
              validator: (v) =>
                  double.tryParse((v ?? '').trim()) == null ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _mrp,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'MRP (optional)'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _quantity,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Stock quantity'),
              validator: (v) =>
                  int.tryParse((v ?? '').trim()) == null ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            // Replace the shop product's photo (PATCH image_key on save).
            Row(children: [
              if (_imagePath != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(_imagePath!),
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 56,
                        height: 56,
                        color: scheme.surfaceContainerHighest,
                        child: const Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: _uploadingImage ? null : _pickImage,
                icon: _uploadingImage
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child:
                            CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add_photo_alternate_outlined),
                label: Text(_image == null
                    ? 'Replace photo'
                    : 'Photo ready — replace again'),
              ),
            ]),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
              label: const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet to create a new product listing for the current shop.
///
/// Only name and price are required (backend ShopkeeperProductCreate);
/// brand / unit / SKU / description / image / availability are optional.
/// No barcode field on purpose — barcodes only enter via the scanner flow.
class ProductCreateSheet extends ConsumerStatefulWidget {
  const ProductCreateSheet({super.key, this.onCreated});

  /// Optional success hook (used by the barcode flow's "add manually" path
  /// to close the scanner after a successful create).
  final VoidCallback? onCreated;

  @override
  ConsumerState<ProductCreateSheet> createState() =>
      _ProductCreateSheetState();
}

class _ProductCreateSheetState extends ConsumerState<ProductCreateSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _mrp = TextEditingController();
  final _quantity = TextEditingController(text: '0');
  final _brand = TextEditingController();
  final _unit = TextEditingController();
  final _sku = TextEditingController();
  final _description = TextEditingController();
  bool _publish = true;
  bool _isAvailable = true;
  bool _saving = false;
  bool _uploadingImage = false;

  /// Confirmed product image (its server-minted key goes into `image_key`).
  MediaObject? _image;
  String? _imagePath;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _mrp.dispose();
    _quantity.dispose();
    _brand.dispose();
    _unit.dispose();
    _sku.dispose();
    _description.dispose();
    super.dispose();
  }

  /// Pick + upload a product image via the shared helper. A failed upload
  /// is non-fatal: the image is optional, so the shopkeeper can keep
  /// creating the product.
  Future<void> _pickImage() async {
    if (_uploadingImage) return;
    final result = await _pickAndUploadProductImage(
      context,
      ref,
      onUploading: (uploading) {
        if (mounted) setState(() => _uploadingImage = uploading);
      },
    );
    if (result == null || !mounted) return;
    setState(() {
      _image = result.$1;
      _imagePath = result.$2;
    });
  }

  void _removeImage() {
    setState(() {
      _image = null;
      _imagePath = null;
    });
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final ok = await ref.read(productsControllerProvider.notifier).createProduct(
          name: _name.text.trim(),
          price: double.parse(_price.text.trim()),
          mrp: double.tryParse(_mrp.text.trim()),
          unit: _unit.text.trim(),
          sku: _sku.text.trim(),
          brand: _brand.text.trim(),
          description: _description.text.trim(),
          imageKey: _image?.key,
          isAvailable: _isAvailable,
          quantity: int.tryParse(_quantity.text.trim()) ?? 0,
          publish: _publish,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context);
    widget.onCreated?.call();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Product created' : 'Could not create product'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(
                    child: Text('New product',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close)),
                ]),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration:
                      const InputDecoration(labelText: 'Product name *'),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Name is required' : null,
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _price,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration:
                          const InputDecoration(labelText: 'Selling price *'),
                      validator: (v) => double.tryParse((v ?? '').trim()) == null
                          ? 'Required'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _mrp,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'MRP'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _quantity,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Quantity (initial stock)'),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _brand,
                      textCapitalization: TextCapitalization.words,
                      decoration:
                          const InputDecoration(labelText: 'Brand (optional)'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _unit,
                      decoration: const InputDecoration(
                          labelText: 'Unit / size (e.g. 1 kg)'),
                    ),
                  ),
                ]),
                // Optional details stay collapsed so the essential fields
                // (name + price) remain front and center.
                Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 8),
                    title: const Text('More details (optional)'),
                    children: [
                      TextFormField(
                        controller: _sku,
                        decoration: const InputDecoration(
                            labelText: 'SKU (optional)'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _description,
                        minLines: 2,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                            labelText: 'Description (optional)'),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Available for sale'),
                        subtitle: const Text(
                            'Unavailable products are hidden from customers'),
                        value: _isAvailable,
                        onChanged: (v) => setState(() => _isAvailable = v),
                      ),
                      const SizedBox(height: 4),
                      Row(children: [
                        if (_imagePath != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(_imagePath!),
                                width: 56,
                                height: 56,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  width: 56,
                                  height: 56,
                                  color: scheme.surfaceContainerHighest,
                                  child: const Icon(
                                      Icons.broken_image_outlined),
                                ),
                              ),
                            ),
                          ),
                        OutlinedButton.icon(
                          onPressed: _uploadingImage ? null : _pickImage,
                          icon: _uploadingImage
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Icon(Icons.add_photo_alternate_outlined),
                          label: Text(_image == null
                              ? 'Add product photo'
                              : 'Replace photo'),
                        ),
                        if (_image != null)
                          IconButton(
                            tooltip: 'Remove photo',
                            onPressed: _removeImage,
                            icon: const Icon(Icons.delete_outline),
                          ),
                      ]),
                      const SizedBox(height: 4),
                      Text(
                        'JPG / PNG / WebP up to 5 MB, stored securely — '
                        'the shop listing shows a link to it.',
                        style: TextStyle(fontSize: 11, color: scheme.outline),
                      ),
                    ],
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Publish immediately'),
                  subtitle: const Text('Unpublished products stay as drafts'),
                  value: _publish,
                  onChanged: (v) => setState(() => _publish = v),
                ),
                FilledButton.icon(
                  onPressed: _saving ? null : _create,
                  icon: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.add),
                  label: const Text('Create product'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}



/// Req 24: the single "Add product" entry point. The FAB (and every other
/// add affordance) opens this chooser first so the shopkeeper picks the
/// method explicitly: manual entry, barcode scan, bulk Excel — POS sync
/// stays visible-but-disabled until POS integration ships.
class ProductAddMethodSheet extends StatelessWidget {
  const ProductAddMethodSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      // Scrollable so larger accessibility font scales / short screens can
      // never overflow the sheet (content is compact but not fixed-height).
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Add product', style: theme.textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Choose how you want to add products:',
                style: TextStyle(fontSize: 13, color: theme.colorScheme.outline),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.edit_note_outlined),
              title: const Text('Enter manually'),
              subtitle: const Text('Full details: price, stock, brand, photo…'),
              onTap: () {
                Navigator.pop(context);
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const ProductCreateSheet(),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_scanner_outlined),
              title: const Text('Scan barcode'),
              subtitle: const Text('Match against the shared catalog'),
              onTap: () {
                Navigator.pop(context);
                context.push(Routes.scanBarcode);
              },
            ),
            ListTile(
              leading: const Icon(Icons.table_view_outlined),
              title: const Text('Bulk Excel import'),
              subtitle: const Text('Upload a spreadsheet of products'),
              onTap: () {
                Navigator.pop(context);
                context.push(Routes.inventoryImport);
              },
            ),
            ListTile(
              enabled: false,
              leading: const Icon(Icons.point_of_sale_outlined),
              title: const Text('POS sync'),
              subtitle: const Text('Available after POS integration'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
