import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/list_loading_view.dart';
import '../../../../core/widgets/skeletons.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../settings/presentation/controllers/settings_controller.dart';
import '../controllers/notification_preferences_controller.dart';

/// Dedicated notification preferences screen.
///
/// ── Why this screen only shows what the backend can honour ────────────────
/// Every category switch here writes to `notification_preferences` via
/// `NotificationPreferences.toApiJson()`, whose fields are fixed by
/// `NotificationPreferencesPayload` (API contract §21.4). The backend
/// decision table (`notification_service._TYPE_REGISTRY`) gates:
///
///   PRICE_DROP        -> price_alerts
///   PRODUCT_AVAILABLE -> availability_alerts
///   OFFER             -> deal_alerts
///
/// A toggle with no backing column would be a switch that *looks* like
/// control but silently does nothing once the customer is signed in — worse
/// than not offering it. So this screen offers the supported categories, the
/// delivery channels the backend stores (`email_enabled`, `sms_enabled`),
/// and the master device switch (`pushNotificationsEnabled`), which is local
/// and additionally drives device-token registration.
///
/// Deliberately NOT offered, because the backend has no field for them:
///   * **Shop updates** — no `shop_updates` column exists. The
///     `SHOP_VERIFICATION` / `SHOP_OFFER` types are shopkeeper-facing.
///   * **System messages** — `SYSTEM` is `Audience.ADMIN` and documented as
///     service-critical, never gated.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final deviceController = ref.read(settingsControllerProvider.notifier);
    final authState = ref.watch(authControllerProvider);
    // Preferences are account-scoped, so a guest cannot persist them.
    final isGuest = authState.status != AuthStatus.authenticated;
    final state = ref.watch(notificationPreferencesControllerProvider);

    // A failed save must be visible: the switch is optimistic, so without this
    // the customer would see their new value and have no idea it never saved.
    ref.listen<NotificationPreferencesState>(
      notificationPreferencesControllerProvider,
      (previous, next) {
        if (next.error != null && previous?.error == null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(next.error!),
                behavior: SnackBarBehavior.floating,
              ),
            );
        }
      },
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: state.isLoading
          // The switches arrive as a fixed, known list — so the placeholder is
          // that list, not a lone spinner in an empty page. A full-screen
          // spinner here would imply the shape of this screen was unknowable
          // when it is hard-coded directly below.
          ? const ListLoadingView(
              message: 'Loading your preferences…',
              shape: SkeletonRowShape.tile,
            )
          : ListView(
              children: [
                // ── Delivery on this device ────────────────────────────
                const SectionLabel('On this device'),
                SwitchListTile(
                  key: const Key('notifMasterSwitch'),
                  secondary: Icon(
                    Icons.notifications_active,
                    color: settings.pushNotificationsEnabled
                        ? AppColors.primary
                        : AppColors.textMuted,
                  ),
                  title: const Text('Push notifications'),
                  subtitle: const Text(
                    'Master switch for alerts on this device',
                  ),
                  value: settings.pushNotificationsEnabled,
                  onChanged: deviceController.toggleNotifications,
                ),
                const Divider(indent: AppSpacing.md),
                const SectionLabel('What you get alerted about'),
                const _PrefSwitch(
                  key: Key('notifPriceUpdates'),
                  field: _PrefField.price,
                  icon: Icons.sell_outlined,
                  title: 'Price updates',
                  subtitle: 'When a watched product gets cheaper nearby',
                ),
                const _PrefSwitch(
                  key: Key('notifAvailabilityUpdates'),
                  field: _PrefField.availability,
                  icon: Icons.inventory_2_outlined,
                  title: 'Availability updates',
                  subtitle: 'When an out-of-stock product is back',
                ),
                const _PrefSwitch(
                  key: Key('notifOffers'),
                  field: _PrefField.offers,
                  icon: Icons.local_offer_outlined,
                  title: 'Offers and deals',
                  subtitle: 'Promotions and personalised discounts',
                ),
                const Divider(indent: AppSpacing.md),
                const SectionLabel('Other delivery channels'),
                const _PrefSwitch(
                  key: Key('notifEmailChannel'),
                  field: _PrefField.email,
                  icon: Icons.mail_outline,
                  title: 'Email',
                  subtitle: 'Send a copy of alerts to your email',
                ),
                const _PrefSwitch(
                  key: Key('notifSmsChannel'),
                  field: _PrefField.sms,
                  icon: Icons.sms_outlined,
                  title: 'SMS',
                  subtitle: 'Send a copy of alerts as text messages',
                ),
                if (isGuest) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Card(
                      elevation: 0,
                      color: AppColors.primary.withValues(alpha: 0.06),
                      child: ListTile(
                        leading: const Icon(Icons.login),
                        title: const Text('Sign in to sync your choices'),
                        subtitle: const Text(
                          'Your selections are kept on this device until you '
                          'sign in, then saved to your account.',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/login'),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
    );
  }
}

/// Which backend field a switch is bound to.
///
/// An explicit enum (rather than keying off the widget `Key` or the display
/// title) keeps the UI-to-API mapping in one readable place and impossible to
/// break by renaming a label.
enum _PrefField { price, availability, offers, email, sms }

/// A single backend-backed preference switch.
///
/// Reads its current value and writes through
/// [NotificationPreferencesController], so the value shown and the value sent
/// to `PUT /notifications/preferences` can never drift apart.
class _PrefSwitch extends ConsumerWidget {
  const _PrefSwitch({
    super.key,
    required this.field,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final _PrefField field;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(
      notificationPreferencesControllerProvider.select((s) => s.preferences),
    );
    final controller = ref.read(
      notificationPreferencesControllerProvider.notifier,
    );

    final (value, onChanged) = switch (field) {
      _PrefField.price => (prefs.priceAlerts, controller.setPriceAlerts),
      _PrefField.availability => (
        prefs.availabilityAlerts,
        controller.setAvailabilityAlerts,
      ),
      // "Offers" is one customer-facing idea backed by two backend fields
      // (`promotional` and `deal_alerts`). Turning it on enables both and
      // turning it off disables both — otherwise the switch would read "on"
      // while the backend still suppressed every offer.
      _PrefField.offers => (
        prefs.promotional || prefs.dealAlerts,
        controller.setOffers,
      ),
      _PrefField.email => (prefs.emailEnabled, controller.setEmail),
      _PrefField.sms => (prefs.smsEnabled, controller.setSms),
    };

    return SwitchListTile(
      secondary: Icon(icon, size: 22, color: AppColors.textMuted),
      title: Text(title, style: const TextStyle(fontSize: 15)),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }
}
