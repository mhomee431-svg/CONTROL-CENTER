import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/shop_models.dart';
import '../controllers/shop_profile_controller.dart';
import '../widgets/shop_profile_shared.dart';

/// Edit Shop — one form for every whitelisted profile field
/// (`PUT /shopkeeper/shops/{id}/profile`). Only the fields the shopkeeper
/// actually changed are sent, so an untouched optional field can never wipe a
/// stored value.
class EditShopScreen extends ConsumerStatefulWidget {
  const EditShopScreen({super.key});

  @override
  ConsumerState<EditShopScreen> createState() => _EditShopScreenState();
}

class _EditShopScreenState extends ConsumerState<EditShopScreen> {
  final _formKey = GlobalKey<FormState>();
  late final List<TextEditingController> _c = [
    for (var i = 0; i < 7; i++) TextEditingController(),
  ];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final state = ref.read(shopProfileDetailProvider);
      if (state.status != ShopProfileStatus.ready) {
        ref.read(shopProfileDetailProvider.notifier).load();
      }
    });
  }

  @override
  void dispose() {
    for (final controller in _c) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Binds the loaded payload into the controllers exactly once.
  void _bind(ShopDetail detail) {
    if (_c.first.text.isNotEmpty) return;
    _c[0].text = detail.summary.name;
    _c[1].text = detail.tagline ?? '';
    _c[2].text = detail.description ?? '';
    _c[3].text = detail.phone ?? '';
    _c[4].text = detail.alternatePhone ?? '';
    _c[5].text = detail.whatsappNumber ?? '';
    _c[6].text = detail.email ?? '';
  }

  Future<void> _save(ShopDetail detail) async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final fields = <String, dynamic>{};
    void put(String key, String current, TextEditingController c) {
      final value = c.text.trim();
      if (value != current.trim()) {
        // An emptied optional field is sent as an empty string — the backend
        // whitelist treats that as "clear this field".
        fields[key] = value;
      }
    }

    put('name', detail.summary.name, _c[0]);
    put('tagline', detail.tagline ?? '', _c[1]);
    put('description', detail.description ?? '', _c[2]);
    put('phone', detail.phone ?? '', _c[3]);
    put('alternate_phone', detail.alternatePhone ?? '', _c[4]);
    put('whatsapp_number', detail.whatsappNumber ?? '', _c[5]);
    put('email', detail.email ?? '', _c[6]);

    if (fields.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing changed yet.')),
      );
      return;
    }

    setState(() => _saving = true);
    final ok = await ref
        .read(shopProfileDetailProvider.notifier)
        .saveProfileFields(fields);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Shop profile updated' : 'Update failed. Please retry.',
        ),
      ),
    );
  }

  String? _requiredName(String? value) =>
      (value ?? '').trim().isEmpty ? 'Shop name is required' : null;

  String? _optionalEmail(String? value) {
    final email = (value ?? '').trim();
    if (email.isEmpty) return null;
    return email.contains('@') && email.contains('.')
        ? null
        : 'Enter a valid email address';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(shopProfileDetailProvider);
    final canEdit = shopCanEdit(ref);

    return Scaffold(
      appBar: AppBar(title: const Text('Edit shop')),
      body: SafeArea(
        child: ShopModuleBody(
          state: state,
          onRetry: () => ref.read(shopProfileDetailProvider.notifier).load(),
          builder: (context, detail) {
            _bind(detail);
            return Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    key: const Key('shop-edit-name'),
                    controller: _c[0],
                    enabled: canEdit,
                    validator: _requiredName,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Shop name',
                      prefixIcon: Icon(Icons.storefront_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('shop-edit-tagline'),
                    controller: _c[1],
                    enabled: canEdit,
                    maxLength: 255,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Tagline',
                      hintText: 'A one-line pitch customers see first',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('shop-edit-description'),
                    controller: _c[2],
                    enabled: canEdit,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Contact',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const Key('shop-edit-phone'),
                    controller: _c[3],
                    enabled: canEdit,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Phone',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('shop-edit-alt-phone'),
                    controller: _c[4],
                    enabled: canEdit,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Alternate phone',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('shop-edit-whatsapp'),
                    controller: _c[5],
                    enabled: canEdit,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'WhatsApp number',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('shop-edit-email'),
                    controller: _c[6],
                    enabled: canEdit,
                    keyboardType: TextInputType.emailAddress,
                    validator: _optionalEmail,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  if (!canEdit) ...[
                    const SizedBox(height: 8),
                    const ShopPermissionNotice(),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    key: const Key('shop-edit-save'),
                    onPressed:
                        (_saving || !canEdit) ? null : () => _save(detail),
                    icon: _saving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: const Text('Save changes'),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'Only the fields you changed are sent to the server.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}