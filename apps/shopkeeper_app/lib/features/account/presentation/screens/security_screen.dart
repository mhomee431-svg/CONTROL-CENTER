import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/app_text.dart';
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
      appBar: AppBar(title: Text(appText(context).commonSecurity2)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            SettingsIntro(
              icon: Icons.shield_outlined,
              title: appText(context).commonAccountProtection,
              subtitle: appText(context).securityScreenHowYouSignInAnd,
            ),
            SettingsSection(
              title: appText(context).commonSignIn2,
              children: [
                SettingsTile(
                  icon: Icons.verified_user_outlined,
                  title: appText(context).commonSignInMethod,
                  subtitle: appText(context).securityScreenGoogleAccountVerifiedByFirebase,
                ),
                SettingsTile(
                  icon: Icons.mail_outline,
                  title: appText(context).commonSignedInAs,
                  subtitle: user?.email ?? user?.phoneNumber ?? 'Not available',
                ),
                SettingsTile(
                  icon: Icons.badge_outlined,
                  title: appText(context).commonAccessOnThisAccount,
                  subtitle: role,
                ),
                SettingsTile(
                  icon: Icons.check_circle_outline,
                  title: appText(context).commonAccountStatus,
                  subtitle: _statusLabel(user?.status),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SettingsNotice(
              icon: Icons.lock_outline,
              title: appText(context).securityScreenPasswordSignInIsNot,
              message: appText(context).securityScreenYourIdentityIsVerifiedBy,
            ),
            const SizedBox(height: 8),
            SettingsSection(
              title: appText(context).commonSession,
              children: [
                SettingsTile(
                  icon: Icons.devices_outlined,
                  title: appText(context).commonActiveSession,
                  subtitle: appText(context).commonSignedInOnThisDevice,
                  trailingLabel: 'This device',
                ),
                SettingsTile(
                  key: const Key('security_logout'),
                  icon: Icons.logout,
                  title: appText(context).commonSignOutOfThisDevice2,
                  subtitle: appText(context).securityScreenEndsTheSessionAndErases,
                  isDestructive: true,
                  onTap: () => context.push(Routes.logoutConfirmation),
                ),
              ],
            ),
            SettingsSection(
              title: appText(context).commonAccountSafety,
              footnote: 'Never share your Google password or an OTP with anyone '
                  '— Passly staff will never ask for them.',
              children: [
                SettingsTile(
                  key: const Key('security_notification_preferences'),
                  icon: Icons.notifications_active_outlined,
                  title: appText(context).commonSecurityAlerts,
                  subtitle: appText(context).securityScreenSignInAndAccountNotices,
                  onTap: () => context.push(Routes.notificationPreferences),
                ),
                SettingsTile(
                  icon: Icons.chat_outlined,
                  title: appText(context).securityScreenReportSuspiciousActivity,
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