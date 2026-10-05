import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../core/router/route_names.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../../shops/domain/profile_scope.dart';
import '../../../shops/presentation/widgets/verification_badge.dart';

/// Account & session management for the signed-in shopkeeper.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final user = auth.user;
    final shop = ref.watch(selectedShopProvider);
    final scheme = Theme.of(context).colorScheme;
    // Single-profile MVP: ONE shopkeeper → ONE business, so the entry that
    // opens the business PICKER stays hidden (profile_scope.dart).
    final multiShop = ref.watch(multiShopEnabledProvider);

    return Scaffold(
      appBar: AppBar(title: Text(appText(context).commonAccount)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            InkWell(
              onTap: () => context.push(Routes.profileEdit),
              child: _UserCard(user: user),
            ),
            const SizedBox(height: 16),
            _BusinessCard(shop: shop),
            const SizedBox(height: 8),
            Card(
              clipBehavior: Clip.antiAlias,
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.store_outlined),
                    title: Text(appText(context).commonShopProfile),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(Routes.shopProfile),
                  ),
                  Divider(height: 1, color: Theme.of(context).dividerColor),
                  ListTile(
                    leading: const Icon(Icons.tune),
                    title: Text(appText(context).commonShopSettings),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(Routes.shopSettings),
                  ),
                  // Single-profile MVP: "My business" opened the business
                  // PICKER (`/shops`) — switch / manage multiple businesses, a
                  // future phase (profile_scope.dart). Nothing is lost: the
                  // current business is already shown by `_BusinessCard` above,
                  // and "Shop profile" / "Shop settings" own its management.
                  if (multiShop) ...[
                    Divider(height: 1, color: Theme.of(context).dividerColor),
                    ListTile(
                      leading: const Icon(Icons.store_outlined),
                      title: Text(appText(context).commonMyBusiness),
                      subtitle: shop != null
                          ? Text(
                              shop.name,
                              style: const TextStyle(fontSize: 12),
                            )
                          : Text(
                              appText(context).commonNotEstablishedYet,
                              style: TextStyle(fontSize: 12),
                            ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(Routes.shops),
                    ),
                  ],
                  Divider(height: 1, color: Theme.of(context).dividerColor),
                  ListTile(
                    leading: const Icon(Icons.insights_outlined),
                    title: Text(appText(context).commonReportsInsights),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(Routes.insights),
                  ),
                  Divider(height: 1, color: Theme.of(context).dividerColor),
                  ListTile(
                    leading: const Icon(Icons.apps),
                    title: Text(appText(context).commonAllFeatures),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(Routes.features),
                  ),
                  Divider(height: 1, color: Theme.of(context).dividerColor),
                  ListTile(
                    leading: const Icon(Icons.help_outline),
                    title: Text(appText(context).commonHelpSupport),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(Routes.support),
                  ),
                  Divider(height: 1, color: Theme.of(context).dividerColor),
                  ListTile(
                    key: const Key('account_settings_tile'),
                    leading: const Icon(Icons.settings_outlined),
                    title: Text(appText(context).commonSettings),
                    subtitle: Text(
                      appText(context).accountScreenAccountSecurityAppLegalAnd,
                      style: TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(Routes.accountSettings),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Card(
              clipBehavior: Clip.antiAlias,
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    key: const Key('account_notification_settings_tile'),
                    leading: const Icon(Icons.notifications_outlined),
                    title: Text(appText(context).commonNotificationSettings),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(Routes.notificationSettings),
                  ),
                  Divider(height: 1, color: Theme.of(context).dividerColor),
                  ListTile(
                    leading: Icon(Icons.logout, color: scheme.error),
                    key: const Key('account_logout_tile'),
                    title: Text(
                      appText(context).commonLogOut,
                      style: TextStyle(
                        color: scheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () => context.push(Routes.logoutConfirmation),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                appText(context).accountScreenHyperlocalShopkeeperV100,
                style: TextStyle(fontSize: 12, color: scheme.outline),
              ),
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
        child: Row(
          children: [
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
                  color: scheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user?.displayName ?? 'Shopkeeper',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user?.phoneNumber ?? '',
                    style: TextStyle(fontSize: 13, color: scheme.outline),
                  ),
                  // E-mail is shown only when the backend actually has one —
                  // the card never invents a placeholder address.
                  if (user?.email != null &&
                      (user?.email as String).trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      user!.email!.trim(),
                      style: TextStyle(fontSize: 13, color: scheme.outline),
                    ),
                  ],
                  if (user?.role != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        user.role!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
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
            Text(
              appText(context).commonCurrentBusiness,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            if (shop == null)
              Text(
                appText(context).commonNoShopSelected,
                style: TextStyle(color: scheme.outline),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      shop.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  VerificationBadge(
                    status: shop.isVerified ? 'VERIFIED' : 'PENDING',
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                appText(context).accountScreenValueStatusValue2(
                  shop.membership == 'owner' ? 'Owner' : 'Manager',
                  shop.status,
                  shop.category != null ? ' · ${shop.category}' : '',
                ),
                style: TextStyle(fontSize: 13, color: scheme.outline),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
