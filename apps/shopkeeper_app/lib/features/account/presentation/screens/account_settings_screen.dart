import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../widgets/settings_widgets.dart';

/// SETTINGS — every account-level destination, in five logical groups.
///
/// The Account tab stays a summary (identity card + the business shortcuts a
/// shopkeeper uses daily). This hub owns the long tail, grouped so a shopkeeper
/// knows WHERE to look before they know what the setting is called:
///
///  * **Account**  — who I am, my shop, and getting out (My Profile, Shop
///    Profile, Logout).
///  * **Security** — how I sign in and where I am signed in (Authentication,
///    Sessions & devices). The session rows come straight from the backend, so
///    this group only exists because that endpoint does.
///  * **App**      — how the app behaves on this device (Notifications, Theme,
///    Language, Data & storage, About).
///  * **Legal**    — Privacy Policy, Terms & Conditions.
///  * **Support**  — Help Center, FAQs, Contact Support, Report Issue.
///
/// Every row pushes a real route — nothing here is a placeholder — and the keys
/// are stable so the settings test can prove each group still exists.
///
/// Shop DATA settings (shop settings, holidays, switching businesses) are
/// deliberately NOT repeated here: they live on the Account tab, which keeps
/// one destination per concern.
class AccountSettingsScreen extends ConsumerWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final shop = ref.watch(selectedShopProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
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
              title: 'Account',
              children: [
                SettingsTile(
                  key: const Key('settings_edit_profile'),
                  icon: Icons.person_outline,
                  title: 'My profile',
                  subtitle: (user?.phoneNumber.isNotEmpty ?? false)
                      ? user!.phoneNumber
                      : 'Name, e-mail and photo',
                  onTap: () => context.push(Routes.profileEdit),
                ),
                SettingsTile(
                  key: const Key('settings_shop_profile'),
                  icon: Icons.store_outlined,
                  title: 'Shop profile',
                  subtitle: shop == null ? 'Not established yet' : shop.name,
                  onTap: () => context.push(Routes.shopProfile),
                ),
                SettingsTile(
                  key: const Key('settings_logout'),
                  icon: Icons.logout,
                  title: 'Logout',
                  subtitle: 'Sign out of this device',
                  isDestructive: true,
                  onTap: () => context.push(Routes.logoutConfirmation),
                ),
              ],
            ),
            SettingsSection(
              title: 'Security',
              footnote: 'Sign-in is verified by Google, and the session list is '
                  'read from the server — so it shows what is really signed in.',
              children: [
                SettingsTile(
                  key: const Key('settings_security'),
                  icon: Icons.shield_outlined,
                  title: 'Authentication',
                  subtitle: 'Sign-in method, account status and safety',
                  onTap: () => context.push(Routes.security),
                ),
                SettingsTile(
                  key: const Key('settings_sessions'),
                  icon: Icons.devices_outlined,
                  title: 'Sessions & devices',
                  subtitle: 'Every device signed in to this account',
                  onTap: () => context.push(Routes.sessions),
                ),
              ],
            ),
            SettingsSection(
              title: 'App',
              children: [
                SettingsTile(
                  key: const Key('settings_notification_settings'),
                  icon: Icons.notifications_outlined,
                  title: 'Notifications',
                  subtitle: 'Delivery, categories and permissions',
                  onTap: () => context.push(Routes.notificationSettings),
                ),
                SettingsTile(
                  key: const Key('settings_app_settings'),
                  icon: Icons.palette_outlined,
                  title: 'Theme',
                  subtitle: 'Light, dark or follow this device',
                  onTap: () => context.push(Routes.appSettings),
                ),
                SettingsTile(
                  key: const Key('settings_language'),
                  icon: Icons.language_outlined,
                  title: 'Language',
                  subtitle: 'App language for this device',
                  onTap: () => context.push(Routes.language),
                ),
                SettingsTile(
                  key: const Key('settings_data_storage'),
                  icon: Icons.storage_outlined,
                  title: 'Data & storage',
                  subtitle: 'What is kept on this device',
                  onTap: () => context.push(Routes.dataStorage),
                ),
                SettingsTile(
                  key: const Key('settings_about'),
                  icon: Icons.info_outline,
                  title: 'About',
                  subtitle: 'Version, licences and credits',
                  onTap: () => context.push(Routes.about),
                ),
              ],
            ),
            SettingsSection(
              title: 'Legal',
              children: [
                SettingsTile(
                  key: const Key('settings_privacy'),
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy Policy',
                  subtitle: 'What we collect and why',
                  onTap: () => context.push(Routes.privacy),
                ),
                SettingsTile(
                  key: const Key('settings_terms'),
                  icon: Icons.description_outlined,
                  title: 'Terms & Conditions',
                  subtitle: 'The agreement for using Passly Business',
                  onTap: () => context.push(Routes.terms),
                ),
              ],
            ),
            SettingsSection(
              title: 'Support',
              children: [
                SettingsTile(
                  key: const Key('settings_help_center'),
                  icon: Icons.support_agent_outlined,
                  title: 'Help Center',
                  subtitle: 'Guides and ways to reach the team',
                  onTap: () => context.push(Routes.support),
                ),
                SettingsTile(
                  key: const Key('settings_faqs'),
                  icon: Icons.menu_book_outlined,
                  title: 'FAQs',
                  subtitle: 'Answers to the most common questions',
                  onTap: () => context.push(Routes.faq),
                ),
                SettingsTile(
                  key: const Key('settings_contact_support'),
                  icon: Icons.chat_outlined,
                  title: 'Contact Support',
                  subtitle: 'Message the support team',
                  onTap: () => context.push(Routes.contactSupport),
                ),
                SettingsTile(
                  key: const Key('settings_report_issue'),
                  icon: Icons.bug_report_outlined,
                  title: 'Report Issue',
                  subtitle: 'Tell us what went wrong',
                  onTap: () => context.push(Routes.reportIssue),
                ),
                SettingsTile(
                  key: const Key('settings_my_tickets'),
                  icon: Icons.confirmation_number_outlined,
                  title: 'My Tickets',
                  subtitle: 'Status of the reports you sent',
                  onTap: () => context.push(Routes.myTickets),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const SettingsNotice(
              icon: Icons.storefront_outlined,
              title: 'Looking for your businesses?',
              message: 'Shop settings, holidays and switching between shops '
                  'belong to the Account tab — they change shop data, not your '
                  'account or this app.',
            ),
          ],
        ),
      ),
    );
  }
}