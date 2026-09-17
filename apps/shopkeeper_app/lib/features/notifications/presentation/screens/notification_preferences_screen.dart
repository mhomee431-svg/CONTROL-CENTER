import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../account/presentation/widgets/settings_widgets.dart';
import '../../domain/notification_models.dart';
import '../controllers/notification_preferences_controller.dart';

/// Which alerts the shopkeeper wants, and through which channel.
///
/// The ten switches map 1:1 onto [NotificationPreferences] — the model the
/// backend contract describes for notification settings — so the payload is
/// already correct for the day the server endpoint exists. Until then the
/// selection is persisted on the device, per account (see
/// `notification_preferences_store.dart`); [hasUnsavedChanges] and the save bar
/// are built on that stored snapshot.
class NotificationPreferencesScreen extends ConsumerStatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  ConsumerState<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends ConsumerState<NotificationPreferencesScreen> {
  @override
  void initState() {
    super.initState();
    // A Notifier cannot await inside build(), so the stored values are read
    // once the first frame is up.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(notificationPreferencesProvider.notifier).load();
    });
  }

  Future<void> _save() async {
    final saved =
        await ref.read(notificationPreferencesProvider.notifier).save();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved
              ? 'Notification preferences saved'
              : 'Could not save your preferences. Please try again.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationPreferencesProvider);
    final prefs = state.preferences;

    if (state.status == NotificationPreferencesStatus.loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Notification preferences')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    void update(NotificationPreferences next) =>
        ref.read(notificationPreferencesProvider.notifier).update(next);

    return Scaffold(
      appBar: AppBar(title: const Text('Notification preferences')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  const SettingsIntro(
                    icon: Icons.notifications_active_outlined,
                    title: 'Notification preferences',
                    subtitle: 'Saved for your account on this device',
                  ),
                  SettingsSection(
                    title: 'Channels',
                    footnote: 'A channel that is off receives nothing, no '
                        'matter which alerts are selected below.',
                    children: [
                      SettingsSwitchTile(
                        key: const Key('pref_push_enabled'),
                        icon: Icons.notifications_active_outlined,
                        title: 'Push notifications',
                        subtitle: 'Banners on this device',
                        value: prefs.pushEnabled,
                        onChanged: (v) =>
                            update(prefs.copyWith(pushEnabled: v)),
                      ),
                      SettingsSwitchTile(
                        key: const Key('pref_email_enabled'),
                        icon: Icons.mail_outline,
                        title: 'E-mail',
                        subtitle: 'Sent to your account e-mail',
                        value: prefs.emailEnabled,
                        onChanged: (v) =>
                            update(prefs.copyWith(emailEnabled: v)),
                      ),
                      SettingsSwitchTile(
                        key: const Key('pref_sms_enabled'),
                        icon: Icons.sms_outlined,
                        title: 'SMS',
                        subtitle: 'Text message on your registered number',
                        value: prefs.smsEnabled,
                        onChanged: (v) => update(prefs.copyWith(smsEnabled: v)),
                      ),
                    ],
                  ),
                  SettingsSection(
                    title: 'Shop alerts',
                    children: [
                      SettingsSwitchTile(
                        key: const Key('pref_inventory_alerts'),
                        icon: Icons.inventory_2_outlined,
                        title: 'Inventory updates',
                        subtitle: 'Stock and price sync results',
                        value: prefs.inventoryAlerts,
                        onChanged: (v) =>
                            update(prefs.copyWith(inventoryAlerts: v)),
                      ),
                      SettingsSwitchTile(
                        key: const Key('pref_low_stock_alerts'),
                        icon: Icons.production_quantity_limits_outlined,
                        title: 'Low stock',
                        subtitle: 'When a product reaches its reorder level',
                        value: prefs.lowStockAlerts,
                        onChanged: (v) =>
                            update(prefs.copyWith(lowStockAlerts: v)),
                      ),
                      SettingsSwitchTile(
                        key: const Key('pref_order_alerts'),
                        icon: Icons.shopping_bag_outlined,
                        title: 'Orders',
                        subtitle: 'New orders and payment updates',
                        value: prefs.orderAlerts,
                        onChanged: (v) =>
                            update(prefs.copyWith(orderAlerts: v)),
                      ),
                      SettingsSwitchTile(
                        key: const Key('pref_offer_alerts'),
                        icon: Icons.local_offer_outlined,
                        title: 'Offers',
                        subtitle: 'Offer performance and expiry reminders',
                        value: prefs.offerAlerts,
                        onChanged: (v) =>
                            update(prefs.copyWith(offerAlerts: v)),
                      ),
                    ],
                  ),
                  SettingsSection(
                    title: 'Other',
                    children: [
                      SettingsSwitchTile(
                        key: const Key('pref_promotional'),
                        icon: Icons.campaign_outlined,
                        title: 'Promotions and tips',
                        subtitle: 'Product news and selling tips from Passly',
                        value: prefs.promotional,
                        onChanged: (v) =>
                            update(prefs.copyWith(promotional: v)),
                      ),
                      SettingsSwitchTile(
                        key: const Key('pref_security_alerts'),
                        icon: Icons.shield_outlined,
                        title: 'Security alerts',
                        subtitle: 'Sign-in and account-safety notices',
                        value: prefs.securityAlerts,
                        onChanged: (v) =>
                            update(prefs.copyWith(securityAlerts: v)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const SettingsNotice(
                    icon: Icons.inbox_outlined,
                    title: 'The Alerts tab always works',
                    message: 'In-app alerts are part of the app and are never '
                        'switched off. The channels above only control how you '
                        'are reached OUTSIDE the app.',
                  ),
                  const SizedBox(height: 8),
                  SettingsTile(
                    icon: Icons.phonelink_lock_outlined,
                    title: 'Device notification permission',
                    subtitle: 'Banners and sounds are controlled by your phone',
                    onTap: () => context.push(Routes.notificationSettings),
                  ),
                ],
              ),
            ),
            if (state.hasUnsavedChanges)
              _UnsavedChangesBar(
                saving: state.saving,
                onSave: _save,
                onDiscard: () => ref
                    .read(notificationPreferencesProvider.notifier)
                    .discardChanges(),
              ),
          ],
        ),
      ),
    );
  }
}

/// Sticky footer shown only while the selection differs from what is stored, so
/// the shopkeeper can never lose an edit silently.
class _UnsavedChangesBar extends StatelessWidget {
  const _UnsavedChangesBar({
    required this.saving,
    required this.onSave,
    required this.onDiscard,
  });

  final bool saving;
  final Future<void> Function() onSave;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'You have unsaved changes',
                style: TextStyle(fontSize: 12, color: scheme.outline),
              ),
            ),
            TextButton(
              key: const Key('pref_discard_button'),
              onPressed: saving ? null : onDiscard,
              child: const Text('Discard'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('pref_save_button'),
              onPressed: saving ? null : () => onSave(),
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}