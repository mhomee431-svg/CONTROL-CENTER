import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/shop_models.dart';
import '../controllers/shops_controller.dart';

/// Shop registration wizard — creates the shop and makes the current
/// user its primary owner on the backend.
class ShopRegisterScreen extends ConsumerStatefulWidget {
  const ShopRegisterScreen({super.key});

  @override
  ConsumerState<ShopRegisterScreen> createState() =>
      _ShopRegisterScreenState();
}

class _ShopRegisterScreenState extends ConsumerState<ShopRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _tagline = TextEditingController();
  final _description = TextEditingController();
  final _phone = TextEditingController();
  final _gstin = TextEditingController();
  final _addressLine = TextEditingController();
  final _city = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _pincode = TextEditingController();
  final _lat = TextEditingController(text: '12.9716');
  final _lng = TextEditingController(text: '77.5946');
  String _category = 'GROCERY';

  @override
  void dispose() {
    for (final c in [
      _name, _tagline, _description, _phone, _gstin,
      _addressLine, _city, _stateCtrl, _pincode, _lat, _lng,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final payload = <String, dynamic>{
      'name': _name.text.trim(),
      'category': _category,
      if (_tagline.text.trim().isNotEmpty) 'tagline': _tagline.text.trim(),
      if (_description.text.trim().isNotEmpty)
        'description': _description.text.trim(),
      if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
      if (_gstin.text.trim().isNotEmpty) 'gstin': _gstin.text.trim(),
      'latitude': double.tryParse(_lat.text.trim()) ?? 0.0,
      'longitude': double.tryParse(_lng.text.trim()) ?? 0.0,
      'address': {
        'address_line1': _addressLine.text.trim(),
        'city': _city.text.trim(),
        'state': _stateCtrl.text.trim(),
        'pincode': _pincode.text.trim(),
      },
    };
    final ok =
        await ref.read(shopsControllerProvider.notifier).registerShop(payload);
    if (!mounted) return;
    if (ok) {
      context.go('/dashboard');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ref.read(shopsControllerProvider).errorMessage ??
              'Registration failed'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final submitting = ref.watch(shopsControllerProvider
        .select((s) => s.status == ShopsStatus.loading));
    return Scaffold(
      appBar: AppBar(title: const Text('Register a new shop')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: _buildFormFields(submitting),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildFormFields(bool submitting) => [
        Text('Business details',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        TextFormField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Shop name *'),
          validator: (v) =>
              (v ?? '').trim().isEmpty ? 'Shop name is required' : null,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _category,
          decoration: const InputDecoration(labelText: 'Category'),
          items: [
            for (final c in kShopCategories)
              DropdownMenuItem(value: c, child: Text(c)),
          ],
          onChanged: (v) => setState(() => _category = v ?? 'GROCERY'),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _tagline,
          decoration: const InputDecoration(labelText: 'Tagline (optional)'),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _description,
          maxLines: 2,
          decoration:
              const InputDecoration(labelText: 'Description (optional)'),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration:
                  const InputDecoration(labelText: 'Contact phone'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: _gstin,
              decoration:
                  const InputDecoration(labelText: 'GSTIN (optional)'),
            ),
          ),
        ]),
        ..._buildAddressSection(),
        ..._buildSubmitSection(submitting),
      ];

  List<Widget> _buildAddressSection() => [
        const SizedBox(height: 24),
        Text('Location & address',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        TextFormField(
          controller: _addressLine,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Address line *'),
          validator: (v) =>
              (v ?? '').trim().isEmpty ? 'Address is required' : null,
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextFormField(
              controller: _city,
              decoration: const InputDecoration(labelText: 'City *'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: _stateCtrl,
              decoration: const InputDecoration(labelText: 'State *'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: _pincode,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Pincode *'),
              validator: (v) =>
                  (v ?? '').trim().length < 3 ? 'Required' : null,
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextFormField(
              controller: _lat,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Latitude *'),
              validator: (v) {
                final d = double.tryParse((v ?? '').trim());
                if (d == null || d < -90 || d > 90) return '-90 to 90';
                return null;
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: _lng,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Longitude *'),
              validator: (v) {
                final d = double.tryParse((v ?? '').trim());
                if (d == null || d < -180 || d > 180) return '-180 to 180';
                return null;
              },
            ),
          ),
        ]),
      ];

  List<Widget> _buildSubmitSection(bool submitting) => [
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: submitting ? null : _submit,
          icon: submitting
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.storefront),
          label: const Text('Register shop'),
        ),
        const SizedBox(height: 32),
      ];
}

