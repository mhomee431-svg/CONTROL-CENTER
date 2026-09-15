import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../../shops/presentation/widgets/verification_badge.dart';

/// Account & session management for the signed-in shopkeeper.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content:
            const Text('You will need to sign in with your Google account again.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Log out')),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final user = auth.user;
    final shop = ref.watch(selectedShopProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _UserCard(user: user),
            const SizedBox(height: 16),
            _BusinessCard(shop: shop),
            const SizedBox(height: 8),
            Card(
              clipBehavior: Clip.antiAlias,
              margin: EdgeInsets.zero,
              child: Column(children: [
                ListTile(
                  leading: const Icon(Icons.store_outlined),
                  title: const Text('Shop profile'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/shop-profile'),
                ),
                Divider(height: 1, color: Theme.of(context).dividerColor),
                ListTile(
                  leading: const Icon(Icons.tune),
                  title: const Text('Shop settings'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/shop-settings'),
                ),
                Divider(height: 1, color: Theme.of(context).dividerColor),
                ListTile(
                  leading: const Icon(Icons.store_outlined),
                  title: const Text('My business'),
                  subtitle: shop != null
                      ? Text(shop.name, style: const TextStyle(fontSize: 12))
                      : const Text('Not established yet',
                          style: TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/shops'),
                ),
                Divider(height: 1, color: Theme.of(context).dividerColor),
                ListTile(
                  leading: const Icon(Icons.insights_outlined),
                  title: const Text('Reports & insights'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/insights'),
                ),
                Divider(height: 1, color: Theme.of(context).dividerColor),
                ListTile(
                  leading: const Icon(Icons.apps),
                  title: const Text('All features'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/features'),
                ),
                Divider(height: 1, color: Theme.of(context).dividerColor),
                ListTile(
                  leading: const Icon(Icons.help_outline),
                  title: const Text('Help & support'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/support'),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            Card(
              clipBehavior: Clip.antiAlias,
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: Icon(Icons.logout, color: scheme.error),
                key: const Key('account_logout_tile'),
                title: Text('Log out',
                    style: TextStyle(
                        color: scheme.error,
                        fontWeight: FontWeight.w600)),
                onTap: () => _confirmLogout(context, ref),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: Text('Hyperlocal Shopkeeper v1.0.0',
                  style: TextStyle(fontSize: 12, color: scheme.outline)),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.user});

  final dynamic user;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: scheme.primaryContainer,
            child: Text(
              (user == null || user.displayName.isEmpty)
                  ? '?'
                  : user.displayName[0].toUpperCase(),
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: scheme.primary),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user?.displayName ?? 'Shopkeeper',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(user?.phoneNumber ?? '',
                    style:
                        TextStyle(fontSize: 13, color: scheme.outline)),
                if (user?.role != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(user.role!,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: scheme.primary)),
                  ),
                ],
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _BusinessCard extends StatelessWidget {
  const _BusinessCard({required this.shop});

  final dynamic shop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current business',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (shop == null)
              Text('No shop selected', style: TextStyle(color: scheme.outline))
            else ...[
              Row(children: [
                Expanded(
                  child: Text(shop.name,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                VerificationBadge(
                    status: shop.isVerified ? 'VERIFIED' : 'PENDING'),
              ]),
              const SizedBox(height: 4),
              Text(
                '${shop.membership == 'owner' ? 'Owner' : 'Manager'} · ${shop.status}'
                '${shop.category != null ? ' · ${shop.category}' : ''}',
                style: TextStyle(fontSize: 13, color: scheme.outline),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

