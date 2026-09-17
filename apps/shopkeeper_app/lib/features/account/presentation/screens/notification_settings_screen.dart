import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../notifications/presentation/controllers/notification_preferences_controller.dart';
import '../../../notifications/presentation/controllers/notifications_controller.dart';
import '../widgets/settings_widgets.dart';

/// How alerts reach the shopkeeper.
///
/// Split of responsibilities (both routes exist, so they must not duplicate
/// each other):
///  * this screen = delivery reality — what the in-app Alerts tab always
///    delivers, how to grant the DEVICE permission, and a summary of the chosen
///    channels;
///  * `NotificationPreferencesScreen` = which categories and channels the
///    shopkeeper wants, persisted per account.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(notificationsControllerProvider).unreadCount;
    final prefs = ref.watch(notificationPreferencesProvider).preferences;

    return Scaffold(
      appBar: AppBar(title: const Text('Notification settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const SettingsIntro(
              icon: Icons.notifications_outlined,
              title: 'Alerts and permissions',
              subtitle: 'What you are told about, and how',
            ),
            SettingsSection(
              title: 'In-app alerts',
              children: [
                SettingsTile(
                  icon: Icons.inbox_outlined,
                  title: 'Alerts tab',
                  subtitle: unread == 0
                      ? 'No unread alerts right now'
                      : '$unread unread alert${unread == 1 ? '' : 's'}',
                  trailingLabel: 'Always on',
                ),
                SettingsTile(
                  key: const Key('notification_settings_edit_preferences'),
                  icon: Icons.tune,
                  title: 'Choose what you receive',
                  subtitle: 'Inventory, orders, offers and more',
                  onTap: () => context.push(Routes.notificationPreferences),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const SettingsNotice(
              icon: Icons.info_outline,
              title: 'In-app alerts cannot be switched off',
              message: 'Low stock, POS sync results and account notices are part '
                  'of the app so a shop is never silently out of date. The '
                  'channels below decide whether you are ALSO reached outside '
                  'the app.',
            ),
            SettingsSection(
              title: 'Channels',
              footnote: 'Change these in Notification preferences.',
              children: [
                SettingsTile(
                  icon: Icons.notifications_active_outlined,
                  title: 'Push notifications',
                  trailingLabel: prefs.pushEnabled ? 'On' : 'Off',
                ),
                SettingsTile(
                  icon: Icons.mail_outline,
                  title: 'E-mail',
                  trailingLabel: prefs.emailEnabled ? 'On' : 'Off',
                ),
                SettingsTile(
                  icon: Icons.sms_outlined,
                  title: 'SMS',
                  trailingLabel: prefs.smsEnabled ? 'On' : 'Off',
                ),
              ],
            ),
            const SizedBox(height: 8),
            const SettingsNotice(
              icon: Icons.phonelink_lock_outlined,
              title: 'Allow notifications on this device',
              message: 'Banners and sounds are controlled by your phone: open '
                  'Settings > Apps > Passly Business > Notifications and turn '
                  'them on. The app cannot change that permission for you.',
            ),
          ],
        ),
      ),
    );
  }
}