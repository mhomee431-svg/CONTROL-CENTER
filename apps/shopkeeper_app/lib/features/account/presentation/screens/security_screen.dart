import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../widgets/settings_widgets.dart';

/// Sign-in method, account protection and the active session.
///
/// Deliberately read-only: the shopkeeper app signs in through Google/Firebase
/// (the MVP has no password or OTP UI), so there is nothing here that would be
/// a fake control. Anything this screen cannot change, it routes to the place
/// that can — support, or the notification preferences.
class SecurityScreen extends ConsumerWidget {
  const SecurityScreen({super.key});

  /// Backend lifecycle status (`ACTIVE`, `SUSPENDED`, ...) in plain language.
  static String _statusLabel(String? status) {
    switch ((status ?? '').toUpperCase()) {
      case 'ACTIVE':
        return 'Active';
      case 'INACTIVE':
        return 'Inactive';
      case 'SUSPENDED':
        return 'Suspended';
      case 'BANNED':
        return 'Blocked';
      default:
        return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final shop = ref.watch(selectedShopProvider);
    final role = shop != null
        ? (shop.isOwner ? 'Owner' : 'Manager')
        : (user?.role ?? 'Not assigned');

    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const SettingsIntro(
              icon: Icons.shield_outlined,
              title: 'Account protection',
              subtitle: 'How you sign in and where you are signed in',
            ),
            SettingsSection(
              title: 'Sign-in',
              children: [
                SettingsTile(
                  icon: Icons.verified_user_outlined,
                  title: 'Sign-in method',
                  subtitle: 'Google account, verified by Firebase',
                ),
                SettingsTile(
                  icon: Icons.mail_outline,
                  title: 'Signed in as',
                  subtitle: user?.email ?? user?.phoneNumber ?? 'Not available',
                ),
                SettingsTile(
                  icon: Icons.badge_outlined,
                  title: 'Access on this account',
                  subtitle: role,
                ),
                SettingsTile(
                  icon: Icons.check_circle_outline,
                  title: 'Account status',
                  subtitle: _statusLabel(user?.status),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SettingsNotice(
              icon: Icons.lock_outline,
              title: 'Password sign-in is not enabled',
              message: 'Your identity is verified by Google every time you sign '
                  'in, so there is no Passly password to change or reset. To '
                  'move your account to a different Google address, contact '
                  'support.',
            ),
            const SizedBox(height: 8),
            SettingsSection(
              title: 'Session',
              children: [
                SettingsTile(
                  icon: Icons.devices_outlined,
                  title: 'Active session',
                  subtitle: 'Signed in on this device',
                  trailingLabel: 'This device',
                ),
                SettingsTile(
                  key: const Key('security_logout'),
                  icon: Icons.logout,
                  title: 'Sign out of this device',
                  subtitle: 'Ends the session and erases the saved tokens',
                  isDestructive: true,
                  onTap: () => context.push(Routes.logoutConfirmation),
                ),
              ],
            ),
            SettingsSection(
              title: 'Account safety',
              footnote: 'Never share your Google password or an OTP with anyone '
                  '— Passly staff will never ask for them.',
              children: [
                SettingsTile(
                  key: const Key('security_notification_preferences'),
                  icon: Icons.notifications_active_outlined,
                  title: 'Security alerts',
                  subtitle: 'Sign-in and account notices',
                  onTap: () => context.push(Routes.notificationPreferences),
                ),
                SettingsTile(
                  icon: Icons.chat_outlined,
                  title: 'Report suspicious activity',
                  onTap: () => context.push(Routes.contactSupport),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}