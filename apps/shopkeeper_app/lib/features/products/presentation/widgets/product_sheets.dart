import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/ui/numeric_input.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../../media/data/media_repository.dart';
import '../../../pos/presentation/controllers/pos_controller.dart';
import '../../domain/category_taxonomy.dart';
import '../../domain/product_form_rules.dart';
import '../../domain/product_image_picker_service.dart';
import '../../domain/product_models.dart';
import '../controllers/category_controller.dart';
import '../controllers/products_controller.dart';
import 'product_form_messages.dart';
import 'product_image_view.dart';

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

  // Validation lives in ProductImagePickerService so the create sheet, the
  // edit sheet and the unit tests all enforce the exact same rules.
  final picker = ref.read(productImagePickerServiceProvider);
  final validation = await picker.pickAndValidate(ProductImagePickSource.files);
  if (validation == null) return null; // user cancelled
  if (!context.mounted) return null;

  if (validation case FileValidationFailure(:final reason)) {
    showMessage(reason);
    return null;
  }
  final success = validation as FileValidationSuccess;

  onUploading(true);
  try {
    final media = await ref.read(mediaRepositoryProvider).upload(
          category: 'PRODUCT_IMAGE',
          filePath: success.file.path,
          contentType: success.mimeType,
          shopId: ref.read(selectedShopProvider)?.id,
        );
    return (media, success.file.path);
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

  /// Readable reason the last save was REJECTED (offline, server, validation).
  ///
  /// Rendered inline so the sheet stays OPEN and every typed value survives:
  /// a rejected save must never close the sheet and destroy the shopkeeper's
  /// work (see `update_price_screen.dart`, which follows the same rule).
  String? _error;

  /// Newly picked replacement image (sent as `image_key` on save).
  MediaObject? _image;
  String? _imagePath;
  bool _uploadingImage = false;

  /// The shopkeeper cleared the photo. Removal cannot be expressed by sending
  /// `image_key: null` — both this client and the backend build their PATCH
  /// payloads with `exclude_none`/`if null` semantics, which would silently
  /// drop the field and keep the old image. It needs its own explicit flag.
  bool _removeImage = false;

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
      // Picking again after a removal means "keep this new one".
      _removeImage = false;
    });
  }

  /// Clears the photo, falling back to the server copy when nothing new was
  /// picked yet (the photo stays visible until the sheet is saved).
  void _clearImage() {
    final serverImage = widget.item.imageUrl;
    setState(() {
      _image = null;
      _imagePath = null;
      _removeImage = serverImage != null && serverImage.isNotEmpty;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final ok = await ref.read(productsControllerProvider.notifier).saveEdits(
          productId: widget.item.id,
          price: double.tryParse(_price.text.trim()),
          mrp: double.tryParse(_mrp.text.trim()),
          quantity: int.tryParse(_quantity.text.trim()),
          imageKey: _image?.key,
          removeImage: _removeImage,
        );
    if (!mounted) return;
    if (!ok) {
      // A rejected write (offline / server / validation) must NOT close the
      // sheet: the typed price, MRP, quantity and picked photo ARE the work.
      // Stay open, report the backend's readable reason inline, and let the
      // shopkeeper retry the exact same values.
      setState(() {
        _saving = false;
        _error = ref.read(productsControllerProvider).message ??
            'Could not update the product. Retry.';
      });
      return;
    }
    setState(() => _saving = false);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(appText(context).commonProductUpdated)),
    );
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
                child: Text(appText(context).productSheetsEditName(widget.item.name),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              IconButton(
                  tooltip: appText(context).commonClose4,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close)),
            ]),
            const SizedBox(height: 8),
            TextFormField(
              controller: _price,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: NumericInput.decimal(),
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(labelText: appText(context).commonSellingPrice),
              validator: (v) =>
                  double.tryParse((v ?? '').trim()) == null ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _mrp,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: NumericInput.decimal(),
              textInputAction: TextInputAction.next,
              decoration:
                  InputDecoration(labelText: appText(context).commonMRPOptional2),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _quantity,
              keyboardType: TextInputType.number,
              inputFormatters: NumericInput.whole(),
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => FocusScope.of(context).unfocus(),
              decoration:
                  InputDecoration(labelText: appText(context).commonStockQuantity),
              validator: (v) =>
                  int.tryParse((v ?? '').trim()) == null ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            // Replace or clear the shop product's photo (PATCH image_key /
            // remove_image on save).
            Row(children: [
              if (_imagePath != null || !_removeImage) ...[
                ProductImageView(
                  localPath: _imagePath,
                  imageUrl: _removeImage ? null : widget.item.imageUrl,
                  width: 56,
                  height: 56,
                  // This preview IS the content (the photo the shopkeeper just
                  // picked), so it needs a name of its own.
                  semanticLabel: 'Selected product image',
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _uploadingImage ? null : _pickImage,
                  icon: _uploadingImage
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(_image == null
                      ? 'Replace photo'
                      : 'Photo ready — replace again'),
                ),
              ),
              // Only offer "remove" when something would actually be removed:
              // a picked-but-unsaved local photo is cleared by re-picking.
              if (_image == null &&
                  widget.item.imageUrl != null &&
                  widget.item.imageUrl!.isNotEmpty)
                IconButton(
                  tooltip: appText(context).commonRemovePhoto,
                  onPressed: _uploadingImage ? null : _clearImage,
                  icon: const Icon(Icons.delete_outline),
                ),
            ]),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const Key('product-edit-error'),
                style: TextStyle(color: scheme.error, fontSize: 13),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
              label: Text(appText(context).commonSaveChanges),
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

  /// Optional identifier — normalised before it is sent (the same strip the
  /// backend applies), so ` 890-1234 5678 ` becomes `89012345678`.
  final _barcode = TextEditingController();
  bool _publish = true;
  bool _isAvailable = true;
  bool _saving = false;
  bool _uploadingImage = false;

  /// Readable reason the last create was REJECTED (offline, server,
  /// validation). Rendered inline so the sheet stays OPEN and every typed
  /// field survives a rejected write.
  String? _error;

  /// Confirmed product image (its server-minted key goes into `image_key`).
  MediaObject? _image;
  String? _imagePath;

  /// Taxonomy selection — both levels are optional by contract, which is why
  /// the dropdowns never block a save.
  int? _categoryId;
  int? _subcategoryId;

  @override
  void initState() {
    super.initState();
    // The taxonomy is cached for the whole session: the first sheet-open
    // fetches it, every later one renders instantly from memory. A failure
    // leaves the form fully usable with a retry beside the dropdowns.
    Future.microtask(
      () => ref.read(categoryControllerProvider.notifier).ensureLoaded(),
    );
  }

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
    _barcode.dispose();
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

  /// Category + subcategory pickers, driven by the cached taxonomy.
  ///
  /// Both levels are OPTIONAL by backend contract, so this section can never
  /// block a save: a fetch that fails shows a retry and the form carries on, a
  /// leaf-only category hides the second dropdown instead of offering an empty
  /// list, and nothing is rendered at all until the taxonomy is resolved.
  Widget _taxonomyFields(BuildContext context) {
    final theme = Theme.of(context);
    final categories = ref.watch(categoryControllerProvider);

    if (categories.status == CategoryLoadStatus.error) {
      return Row(
        children: [
          Expanded(
            child: Text(
              categories.message ?? 'Could not load categories',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
            ),
          ),
          TextButton(
            key: const Key('create-category-retry'),
            onPressed: () =>
                ref.read(categoryControllerProvider.notifier).ensureLoaded(),
            child: Text(appText(context).commonRetry6),
          ),
        ],
      );
    }

    final taxonomy = categories.taxonomy;
    if (taxonomy == null || taxonomy.topLevel.isEmpty) {
      // Loading (or genuinely empty) — the optional fields simply wait.
      return const SizedBox.shrink();
    }

    final children = _categoryId == null
        ? const <CategoryOption>[]
        : taxonomy.childrenOf(_categoryId!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<int>(
          key: const Key('create-category'),
          initialValue: _categoryId,
          decoration: InputDecoration(labelText: appText(context).commonCategoryOptional),
          items: [
            for (final category in taxonomy.topLevel)
              DropdownMenuItem<int>(
                value: category.id,
                child: Text(category.name),
              ),
          ],
          onChanged: (value) => setState(() {
            _categoryId = value;
            // A new parent invalidates the previously chosen child.
            _subcategoryId = null;
          }),
        ),
        // Only shown once the chosen category actually has subcategories.
        if (children.isNotEmpty) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            key: const Key('create-subcategory'),
            initialValue: _subcategoryId,
            decoration:
                InputDecoration(labelText: appText(context).commonSubcategoryOptional),
            items: [
              for (final child in children)
                DropdownMenuItem<int>(
                  value: child.id,
                  child: Text(child.name),
                ),
            ],
            onChanged: (value) => setState(() => _subcategoryId = value),
          ),
        ],
      ],
    );
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
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
          categoryId: _categoryId,
          subcategoryId: _subcategoryId,
          barcode: ProductFormRules.normalizeBarcode(_barcode.text),
        );
    if (!mounted) return;
    if (!ok) {
      // A rejected write (offline / server / validation) must NOT close the
      // sheet: the whole form — name, prices, stock, brand, image, taxonomy —
      // is unsaved work. Stay open, report the readable reason inline, and let
      // the shopkeeper retry without retyping anything.
      setState(() {
        _saving = false;
        _error = ref.read(productsControllerProvider).message ??
            'Could not create the product. Retry.';
      });
      return;
    }
    setState(() => _saving = false);
    Navigator.pop(context);
    widget.onCreated?.call();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(appText(context).commonProductCreated)),
    );
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
                    child: Text(appText(context).commonNewProduct,
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  IconButton(
                      tooltip: appText(context).commonClose4,
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close)),
                ]),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  maxLength: ProductFormRules.nameMaxLength,
                  decoration: InputDecoration(
                    labelText: appText(context).productSheetsProductName,
                    counterText: '',
                  ),
                  validator: (v) =>
                      productFormErrorText(context, ProductFormRules.name(v)),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _price,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      // Signed so the field can hold `-5` and the validator
                      // below can explain why it is rejected.
                      inputFormatters: NumericInput.decimal(allowSign: true),
                      textInputAction: TextInputAction.next,
                      decoration:
                          InputDecoration(labelText: appText(context).productSheetsSellingPrice),
                      validator: (v) => productFormErrorText(
                          context, ProductFormRules.price(v)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _mrp,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: NumericInput.decimal(allowSign: true),
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(labelText: appText(context).commonMRP),
                      // Optional, but must not undercut the price: the backend
                      // rejects that combination.
                      validator: (v) => productFormErrorText(context,
                          ProductFormRules.mrp(v, priceText: _price.text)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _quantity,
                      keyboardType: TextInputType.number,
                      inputFormatters: NumericInput.whole(),
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) =>
                          FocusScope.of(context).unfocus(),
                      decoration: InputDecoration(
                          labelText: appText(context).commonQuantityInitialStock),
                      validator: (v) => productFormErrorText(
                          context, ProductFormRules.quantity(v)),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                _taxonomyFields(context),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _brand,
                      textCapitalization: TextCapitalization.words,
                      maxLength: ProductFormRules.brandMaxLength,
                      decoration: InputDecoration(
                        labelText: appText(context).commonBrandOptional,
                        counterText: '',
                      ),
                      validator: (v) => productFormErrorText(
                          context,
                          ProductFormRules.optionalMax(
                              v, ProductFormRules.brandMaxLength)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _unit,
                      maxLength: ProductFormRules.unitMaxLength,
                      decoration: InputDecoration(
                        labelText: appText(context).commonUnitSizeEG1,
                        counterText: '',
                      ),
                      validator: (v) => productFormErrorText(
                          context,
                          ProductFormRules.optionalMax(
                              v, ProductFormRules.unitMaxLength)),
                    ),
                  ),
                ]),
                // Optional details stay collapsed so the essential fields
                // (name + price) remain front and center.
                Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: AppColors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 8),
                    title: Text(appText(context).commonMoreDetailsOptional),
                    children: [
                      TextFormField(
                        controller: _sku,
                        maxLength: ProductFormRules.skuMaxLength,
                        decoration: InputDecoration(
                          labelText: appText(context).commonSKUOptional,
                          counterText: '',
                        ),
                        validator: (v) => productFormErrorText(
                            context,
                            ProductFormRules.optionalMax(
                                v, ProductFormRules.skuMaxLength)),
                      ),
                      const SizedBox(height: 12),
                      // The manual identifier becomes the product's primary
                      // barcode; separators are stripped on submit, so what the
                      // shopkeeper typed here matches the scanner's value.
                      TextFormField(
                        controller: _barcode,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: appText(context).commonBarcodeOptional,
                          hintText: appText(context).productSheetsTypeOrPasteTheCode,
                        ),
                        validator: (v) => productFormErrorText(
                            context, ProductFormRules.barcode(v)),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _description,
                        minLines: 2,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                            labelText: appText(context).commonDescriptionOptional),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(appText(context).commonAvailableForSale),
                        subtitle: Text(
                            appText(context).productSheetsUnavailableProductsAreHiddenFrom),
                        value: _isAvailable,
                        onChanged: (v) => setState(() => _isAvailable = v),
                      ),
                      const SizedBox(height: 4),
                      Row(children: [
                        if (_imagePath != null) ...[
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            // Same resilient preview as the edit sheet: a
                            // corrupt local file degrades to a broken-image box
                            // instead of throwing out of the build.
                            child: ProductImageView(
                              localPath: _imagePath,
                              // The picked photo is content, so it needs an
                              // accessible name of its own.
                              semanticLabel: 'Selected product image',
                              width: 56,
                              height: 56,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ],
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _uploadingImage ? null : _pickImage,
                            icon: _uploadingImage
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child:
                                        CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.add_photo_alternate_outlined),
                            label: Text(_image == null
                                ? 'Add product photo'
                                : 'Replace photo'),
                          ),
                        ),
                        if (_image != null)
                          IconButton(
                            tooltip: appText(context).commonRemovePhoto,
                            onPressed: _removeImage,
                            icon: const Icon(Icons.delete_outline),
                          ),
                      ]),
                      const SizedBox(height: 4),
                      Text(
                        appText(context).productSheetsJPGPNGWebPUpTo,
                        style: TextStyle(fontSize: 11, color: scheme.outline),
                      ),
                    ],
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(appText(context).commonPublishImmediately2),
                  subtitle: Text(appText(context).productSheetsUnpublishedProductsStayAsDrafts),
                  value: _publish,
                  onChanged: (v) => setState(() => _publish = v),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    key: const Key('product-create-error'),
                    style: TextStyle(color: scheme.error, fontSize: 13),
                  ),
                ],
                FilledButton.icon(
                  onPressed: _saving ? null : _create,
                  icon: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.add),
                  label: Text(appText(context).commonCreateProduct),
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
/// method explicitly: manual entry, barcode scan, bulk Excel — and POS sync,
/// which lights up only when the backend actually offers POS.
class ProductAddMethodSheet extends ConsumerStatefulWidget {
  const ProductAddMethodSheet({super.key});

  @override
  ConsumerState<ProductAddMethodSheet> createState() =>
      _ProductAddMethodSheetState();
}

class _ProductAddMethodSheetState extends ConsumerState<ProductAddMethodSheet> {
  @override
  void initState() {
    super.initState();
    // The POS entry is driven by the real connector catalogue — never by a
    // hard-coded label. One fetch on open, so the tile reflects what the
    // backend actually offers right now.
    Future.microtask(() => ref.read(posControllerProvider.notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pos = ref.watch(posControllerProvider);
    // Either a published provider (nothing connected yet) or an existing
    // connector makes POS usable; anything else keeps the entry visible but
    // inert rather than hiding it.
    final posReady = pos.integration != null || pos.providers.isNotEmpty;
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
              child: Text(appText(context).commonAddProduct2, style: theme.textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                appText(context).productSheetsChooseHowYouWantTo,
                style: TextStyle(fontSize: 13, color: theme.colorScheme.outline),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.edit_note_outlined),
              title: Text(appText(context).commonEnterManually2),
              subtitle: Text(appText(context).productSheetsFullDetailsPriceStockBrand),
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
              title: Text(appText(context).commonScanBarcode3),
              subtitle: Text(appText(context).productSheetsMatchAgainstTheSharedCatalog),
              onTap: () {
                Navigator.pop(context);
                context.push(Routes.scanBarcode);
              },
            ),
            ListTile(
              leading: const Icon(Icons.table_view_outlined),
              title: Text(appText(context).commonBulkExcelImport),
              subtitle: Text(appText(context).productSheetsUploadASpreadsheetOfProducts),
              onTap: () {
                Navigator.pop(context);
                context.push(Routes.inventoryImport);
              },
            ),
            ListTile(
              key: const Key('add-product-pos'),
              enabled: posReady,
              leading: const Icon(Icons.point_of_sale_outlined),
              title: Text(appText(context).commonPOSSync5),
              subtitle: Text(
                posReady
                    ? 'Import products from your connected POS'
                    : 'Available after POS integration',
              ),
              onTap: posReady
                  ? () {
                      Navigator.pop(context);
                      context.push(Routes.pos);
                    }
                  : null,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
