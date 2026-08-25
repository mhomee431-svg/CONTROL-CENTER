import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/token_store.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../data/shop_repository.dart';
import '../../domain/shop_models.dart';
import '../widgets/verification_badge.dart';

/// Shop profile — view + edit whitelisted business information.
class ShopProfileScreen extends ConsumerStatefulWidget {
  const ShopProfileScreen({super.key});

  @override
  ConsumerState<ShopProfileScreen> createState() => _ShopProfileScreenState();
}

class _ShopProfileScreenState extends ConsumerState<ShopProfileScreen> {
  ShopDetail? _detail;
  bool _loading = true;
  String? _error;

  bool get _canEdit =>
      ref.read(selectedShopProvider)?.canManageSettings ?? false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final shop = ref.read(selectedShopProvider);
    if (shop == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) throw Exception('Not signed in');
      final detail =
          await ref.read(shopRepositoryProvider).getShopDetail(shop.id, token);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the shop profile.';
        _loading = false;
      });
    }
  }

  Future<void> _edit(String key, String label, String? current,
      {int maxLines = 1, TextInputType? keyboard}) async {
    final controller = TextEditingController(text: current ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit $label'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: maxLines,
          keyboardType: keyboard,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (saved != true) return;
    final shop = ref.read(selectedShopProvider);
    if (shop == null) return;
    try {
      await ref
          .read(shopRepositoryProvider)
          .updateProfile(
            shop.id,
            {key: controller.text.trim()},
            (await ref.read(tokenStoreProvider).readAccessToken())!,
          );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$label updated')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Update failed. Please retry.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return Scaffold(
      appBar: AppBar(title: const Text('Shop profile'), actions: [
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
      ]),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null || detail == null
                ? Center(child: Text(_error ?? 'Not available'))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Expanded(
                                  child: Text(detail.summary.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge),
                                ),
                                VerificationBadge(
                                    status: detail.verification.status),
                              ]),
                              const SizedBox(height: 4),
                              Text(
                                '${detail.summary.membership == 'owner' ? 'Owner' : 'Manager'} · ${detail.summary.status}',
                                style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outline),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (!_canEdit)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Managers have read-only access to the profile.',
                            style: TextStyle(
                                color:
                                    Theme.of(context).colorScheme.outline),
                          ),
                        )
                      else ...[
                        const SizedBox(height: 8),
                        _row(context, Icons.badge_outlined, 'Name',
                            detail.summary.name,
                            () => _edit('name', 'Shop name',
                                detail.summary.name)),
                        _row(context, Icons.sell_outlined, 'Tagline',
                            detail.tagline ?? '—',
                            () => _edit(
                                'tagline', 'Tagline', detail.tagline)),
                        _row(context, Icons.description_outlined,
                            'Description', detail.description ?? '—',
                            () => _edit('description', 'Description',
                                detail.description,
                                maxLines: 3)),
                        _row(context, Icons.phone_outlined, 'Phone',
                            detail.phone ?? '—',
                            () => _edit('phone', 'Phone', detail.phone,
                                keyboard: TextInputType.phone)),
                        _row(context, Icons.email_outlined, 'Email',
                            detail.email ?? '—',
                            () => _edit('email', 'Email', detail.email,
                                keyboard: TextInputType.emailAddress)),
                        _row(context, Icons.language, 'Website',
                            detail.websiteUrl ?? '—',
                            () => _edit(
                                'website_url', 'Website',
                                detail.websiteUrl)),
                      ],
                    ],
                  ),
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, String value,
      VoidCallback onEdit) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      subtitle: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: IconButton(
          icon: const Icon(Icons.edit_outlined), onPressed: onEdit),
    );
  }
}

