import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../widgets/settings_widgets.dart';

/// Every account-level destination in one place.
///
/// The Account tab stays a summary (identity card + the business shortcuts a
/// shopkeeper uses daily). This hub owns the long tail — preferences, security,
/// legal and support — so that tab does not grow into a fifteen-row list nobody
/// scrolls.
class AccountSettingsScreen extends ConsumerWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final shop = ref.watch(selectedShopProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Account settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            SettingsIntro(
              icon: Icons.manage_accounts_outlined,
              title: user?.displayName ?? 'Your account',
              subtitle: shop == null
                  ? 'No business linked yet'
                  : '${shop.name} - ${shop.isOwner ? 'Owner' : 'Manager'}',
            ),
            SettingsSection(
              title: 'Profile',
              footnote: 'Sign-in details are verified by Google and cannot be '
                  'edited inside the app.',
              children: [
                SettingsTile(
                  key: const Key('settings_edit_profile'),
                  icon: Icons.person_outline,
                  title: 'Edit profile',
                  subtitle: 'Name, e-mail and photo',
                  onTap: () => context.push(Routes.profileEdit),
                ),
                SettingsTile(
                  icon: Icons.phone_outlined,
                  title: 'Phone number',
                  subtitle: (user?.phoneNumber.isNotEmpty ?? false)
                      ? user!.phoneNumber
                      : 'Not available',
                ),
                SettingsTile(
                  icon: Icons.mail_outline,
                  title: 'E-mail',
                  subtitle: user?.email ?? 'Not linked',
                ),
              ],
            ),
            SettingsSection(
              title: 'Business',
              children: [
                SettingsTile(
                  icon: Icons.store_outlined,
                  title: 'Shop profile',
                  subtitle: shop == null ? 'Not established yet' : shop.name,
                  onTap: () => context.push(Routes.shopProfile),
                ),
                SettingsTile(
                  icon: Icons.tune,
                  title: 'Shop settings',
                  subtitle: 'Hours, holidays and order preferences',
                  onTap: () => context.push(Routes.shopSettings),
                ),
                SettingsTile(
                  icon: Icons.swap_horiz,
                  title: 'My businesses',
                  subtitle: 'Registered shops on this account',
                  onTap: () => context.push(Routes.shops),
                ),
              ],
            ),
            SettingsSection(
              title: 'Preferences',
              children: [
                SettingsTile(
                  key: const Key('settings_app_settings'),
                  icon: Icons.palette_outlined,
                  title: 'App settings',
                  subtitle: 'Theme and appearance',
                  onTap: () => context.push(Routes.appSettings),
                ),
                SettingsTile(
                  key: const Key('settings_notification_settings'),
                  icon: Icons.notifications_outlined,
                  title: 'Notification settings',
                  subtitle: 'Delivery and device permissions',
                  onTap: () => context.push(Routes.notificationSettings),
                ),
                SettingsTile(
                  key: const Key('settings_security'),
                  icon: Icons.shield_outlined,
                  title: 'Security',
                  subtitle: 'Sign-in method and active sessions',
                  onTap: () => context.push(Routes.security),
                ),
              ],
            ),
            SettingsSection(
              title: 'Legal & about',
              children: [
                SettingsTile(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy policy',
                  onTap: () => context.push(Routes.privacy),
                ),
                SettingsTile(
                  icon: Icons.description_outlined,
                  title: 'Terms of service',
                  onTap: () => context.push(Routes.terms),
                ),
                SettingsTile(
                  icon: Icons.info_outline,
                  title: 'About this app',
                  onTap: () => context.push(Routes.about),
                ),
              ],
            ),
            SettingsSection(
              title: 'Help',
              children: [
                SettingsTile(
                  icon: Icons.help_outline,
                  title: 'Help centre',
                  subtitle: 'Answers to common questions',
                  onTap: () => context.push(Routes.faq),
                ),
                SettingsTile(
                  icon: Icons.chat_outlined,
                  title: 'Contact support',
                  onTap: () => context.push(Routes.contactSupport),
                ),
                SettingsTile(
                  icon: Icons.bug_report_outlined,
                  title: 'Report an issue',
                  onTap: () => context.push(Routes.reportIssue),
                ),
              ],
            ),
            SettingsSection(
              title: 'Session',
              children: [
                SettingsTile(
                  key: const Key('settings_logout'),
                  icon: Icons.logout,
                  title: 'Log out',
                  subtitle: 'Sign out of this device',
                  isDestructive: true,
                  onTap: () => context.push(Routes.logoutConfirmation),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}