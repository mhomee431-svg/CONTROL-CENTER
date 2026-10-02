import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../notifications/presentation/controllers/notification_permission_controller.dart';
import '../../../notifications/presentation/controllers/notification_preferences_controller.dart';
import '../../../notifications/presentation/controllers/notifications_controller.dart';
import '../widgets/settings_widgets.dart';

/// How alerts reach the shopkeeper.
///
/// Split of responsibilities (both routes exist, so they must not duplicate
/// each other):
///  * this screen = delivery reality — what the in-app Alerts tab always
///    delivers, the live DEVICE permission with its "Enable Notifications"
///    action, and a summary of the chosen channels;
///  * `NotificationPreferencesScreen` = which categories and channels the
///    shopkeeper wants, persisted per account.
///
/// The device permission never blocks anything: when it is off, every alert
/// still arrives in the Alerts tab.
class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  @override
  void initState() {
    super.initState();
    // Re-read the platform status on every open: it can change while the app
    // is backgrounded (the shopkeeper may have used the system settings).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(notificationPermissionProvider.notifier).refresh();
    });
  }

  /// "Enable Notifications" → the OS dialog, then honest feedback.
  Future<void> _enable() async {
    final controller = ref.read(notificationPermissionProvider.notifier);
    await controller.enable();
    if (!mounted) return;
    final message = ref.read(notificationPermissionProvider).message;
    if (message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      controller.clearMessage();
    }
  }

  Future<void> _openSystemSettings() async {
    final opened = await ref
        .read(notificationPermissionProvider.notifier)
        .openSystemSettings();
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(appText(context).notificationSettingsScreenCouldNotOpenYourPhone),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(notificationsControllerProvider).unreadCount;
    final prefs = ref.watch(notificationPreferencesProvider).preferences;
    final permission = ref.watch(notificationPermissionProvider);

    return Scaffold(
      appBar: AppBar(title: Text(appText(context).commonNotificationSettings2)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            SettingsIntro(
              icon: Icons.notifications_outlined,
              title: appText(context).commonAlertsAndPermissions,
              subtitle: appText(context).notificationSettingsScreenWhatYouAreToldAbout,
            ),
            _DevicePermissionCard(
              state: permission,
              onEnable: _enable,
              onOpenSettings: _openSystemSettings,
            ),
            SettingsSection(
              title: appText(context).commonInAppAlerts,
              children: [
                SettingsTile(
                  icon: Icons.inbox_outlined,
                  title: appText(context).commonAlertsTab,
                  subtitle: unread == 0
                      ? 'No unread alerts right now'
                      : '$unread unread alert${unread == 1 ? '' : 's'}',
                  trailingLabel: 'Always on',
                ),
                SettingsTile(
                  key: const Key('notification_settings_edit_preferences'),
                  icon: Icons.tune,
                  title: appText(context).commonChooseWhatYouReceive,
                  subtitle: appText(context).notificationSettingsScreenInventoryOrdersOffersAndMore,
                  onTap: () => context.push(Routes.notificationPreferences),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SettingsNotice(
              icon: Icons.info_outline,
              title: appText(context).notificationSettingsScreenInAppAlertsCannotBe,
              message: appText(context).notificationSettingsScreenLowStockPOSSyncResults,
            ),
            SettingsSection(
              title: appText(context).commonChannels,
              footnote: 'Change these in Notification preferences.',
              children: [
                SettingsTile(
                  icon: Icons.notifications_active_outlined,
                  title: appText(context).commonPushNotifications,
                  trailingLabel: prefs.pushEnabled ? 'On' : 'Off',
                ),
                SettingsTile(
                  icon: Icons.mail_outline,
                  title: appText(context).commonEMail,
                  trailingLabel: prefs.emailEnabled ? 'On' : 'Off',
                ),
                SettingsTile(
                  icon: Icons.sms_outlined,
                  title: appText(context).commonSMS,
                  trailingLabel: prefs.smsEnabled ? 'On' : 'Off',
                ),
              ],
            ),
            const SizedBox(height: 8),
            SettingsNotice(
              icon: Icons.info_outline,
              title: appText(context).notificationSettingsScreenNotificationsNeverBlockTheApp,
              message: appText(context).notificationSettingsScreenIfDeviceNotificationsAreOff,
            ),
          ],
        ),
      ),
    );
  }
}

/// Live device-permission card: current status, the "Enable Notifications"
/// action, and the system-settings route out of a permanent denial.
///
/// Every state explains what still works, so a shopkeeper who says no knows
/// exactly what they keep.
class _DevicePermissionCard extends StatelessWidget {
  const _DevicePermissionCard({
    required this.state,
    required this.onEnable,
    required this.onOpenSettings,
  });

  final NotificationPermissionState state;
  final Future<void> Function() onEnable;
  final Future<void> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final granted = state.isGranted;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  granted
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined,
                  color: granted ? AppColors.green : scheme.outline,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appText(context).notificationSettingsScreenNotificationsOnThisDevice,
                        style: AppTypography.labelLarge,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        _statusDetail(state),
                        style: AppTypography.caption
                            .copyWith(color: scheme.outline, height: 1.35),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  state.statusLabel,
                  key: const Key('notification_permission_status'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    // Deliberately a STATIC label, never a spinner: a settings
                    // screen must stay settleable even while the platform
                    // status is being read (and on a platform that cannot
                    // answer at all).
                    color: state.isChecking
                        ? scheme.outline
                        : (granted ? AppColors.green : scheme.error),
                  ),
                ),
              ],
            ),
            if (!granted && !state.isChecking) ...[
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                key: const Key('notification_enable_button'),
                onPressed: state.requesting ? null : () => onEnable(),
                icon: state.requesting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.notifications_active_outlined),
                label: Text(
                  state.requesting ? 'Asking your phone…' : 'Enable Notifications',
                ),
              ),
              if (state.needsSettings) ...[
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  key: const Key('notification_open_settings_button'),
                  onPressed: () => onOpenSettings(),
                  icon: const Icon(Icons.settings_outlined),
                  label: Text(appText(context).commonOpenSystemSettings),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  appText(context).notificationSettingsScreenYourPhoneWillNotAsk,
                  style: AppTypography.caption
                      .copyWith(color: scheme.outline, height: 1.35),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// What this permission state means for delivery, in plain words.
  static String _statusDetail(NotificationPermissionState state) =>
      switch (state.status) {
        NotificationPermissionStatus.granted =>
          'Your phone may show banners and play sounds for this app.',
        NotificationPermissionStatus.denied =>
          'Banners and sounds are off. Alerts still appear in the Alerts tab.',
        NotificationPermissionStatus.blocked =>
          'Blocked by your phone. Alerts still appear in the Alerts tab.',
        NotificationPermissionStatus.checking =>
          'Reading your phone settings…',
        NotificationPermissionStatus.unknown =>
          'This device does not report a notification permission.',
      };
}