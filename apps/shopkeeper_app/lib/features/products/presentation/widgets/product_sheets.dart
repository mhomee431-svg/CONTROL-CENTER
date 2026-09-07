import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/product_models.dart';
import '../controllers/products_controller.dart';

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

  @override
  void dispose() {
    _price.dispose();
    _mrp.dispose();
    _quantity.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final ok = await ref.read(productsControllerProvider.notifier).saveEdits(
          productId: widget.item.id,
          price: double.tryParse(_price.text.trim()),
          mrp: double.tryParse(_mrp.text.trim()),
          quantity: int.tryParse(_quantity.text.trim()),
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
class ProductCreateSheet extends ConsumerStatefulWidget {
  const ProductCreateSheet({super.key});

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
  bool _publish = true;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _mrp.dispose();
    _quantity.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final ok = await ref.read(productsControllerProvider.notifier).createProduct(
          name: _name.text.trim(),
          price: double.parse(_price.text.trim()),
          mrp: double.tryParse(_mrp.text.trim()),
          quantity: int.tryParse(_quantity.text.trim()) ?? 0,
          publish: _publish,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Product created' : 'Could not create product'),
    ));
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
                  decoration:
                      const InputDecoration(labelText: 'Quantity *'),
                  validator: (v) => int.tryParse((v ?? '').trim()) == null
                      ? 'Required'
                      : null,
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
    );
  }
}

