import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../notifications/presentation/controllers/notification_preferences_controller.dart';
import '../../../profile/presentation/controllers/profile_controller.dart';
import '../../../saved_and_history/domain/saved_and_history_repository.dart';
import '../controllers/settings_controller.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.initialSection});

  /// Optional section to scroll to on open, so profile entries such as
  /// "Notifications" can deep-link to the relevant part of this long page.
  /// Supported: `notifications`, `privacy`.
  final String? initialSection;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _notificationsKey = GlobalKey();
  final _privacyKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSection());
  }

  void _scrollToSection() {
    if (!mounted) return;
    final target = switch (widget.initialSection) {
      'notifications' => _notificationsKey,
      'privacy' => _privacyKey,
      _ => null,
    };
    final targetContext = target?.currentContext;
    if (targetContext == null) return;
    Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    // `ref` is provided by ConsumerState.
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final authState = ref.watch(authControllerProvider);
    final isGuest = authState.status != AuthStatus.authenticated;
    final strings = ref.watch(appStringsProvider);

    // Surface preference save failures as snackbars.
    ref.listen<NotificationPreferencesState>(
      notificationPreferencesControllerProvider,
      (previous, next) {
        if (next.error != null && previous?.error == null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(next.error!),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
    );

    return Scaffold(
      appBar: AppBar(title: Text(strings.get('settingsTitle'))),
      body: ListView(
        children: [
          // ── Notifications ────────────────────────────────────────────
          _SectionHeader('Notifications', key: _notificationsKey),
          SwitchListTile(
            secondary: Icon(
              Icons.notifications_active,
              color: settings.pushNotificationsEnabled
                  ? AppColors.primary
                  : AppColors.textMuted,
            ),
            title: Text(strings.get('pushNotifications')),
            subtitle: const Text('Allow push alerts on this device'),
            value: settings.pushNotificationsEnabled,
            onChanged: controller.toggleNotifications,
          ),
          const _NotificationPreferencesSection(),
          const Divider(indent: AppSpacing.md),

          // ── Location ─────────────────────────────────────────────────
          const _SectionHeader('Location preferences'),
          SwitchListTile(
            secondary: const Icon(Icons.location_on),
            title: Text(strings.get('locationServices')),
            subtitle: const Text('Use GPS to find nearby shops'),
            value: settings.locationEnabled,
            onChanged: controller.toggleLocation,
          ),
          ListTile(
            leading: const Icon(Icons.bookmark_border),
            title: const Text('Default address'),
            subtitle: const Text('Manage saved addresses'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/profile/addresses'),
          ),

          const Divider(indent: AppSpacing.md),

          // ── App preferences ─────────────────────────────────────────
          const _SectionHeader('App preferences'),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(strings.get('language')),
            subtitle: Text(settings.languageCode == 'en' ? 'English' : 'हिंदी'),
            onTap: () => _pickLanguage(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.brightness_6),
            title: Text(strings.get('theme')),
            subtitle: Text(_themeLabel(settings.themeMode)),
            onTap: () => _pickTheme(context, ref),
          ),
          const Divider(indent: AppSpacing.md),

          // ── Privacy ─────────────────────────────────────────────────
          _SectionHeader('Privacy & data', key: _privacyKey),
          SwitchListTile(
            secondary: const Icon(Icons.analytics_outlined),
            title: const Text('Usage analytics'),
            subtitle: const Text('Share anonymous usage data'),
            value: settings.analyticsEnabled,
            onChanged: controller.setAnalytics,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.bug_report_outlined),
            title: const Text('Crash reports'),
            subtitle: const Text('Automatically send crash diagnostics'),
            value: settings.crashReportingEnabled,
            onChanged: controller.setCrashReporting,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.recommend_outlined),
            title: const Text('Personalised recommendations'),
            subtitle: const Text('Suggest items based on your activity'),
            value: settings.personalizedRecommendations,
            onChanged: controller.setPersonalizedRecommendations,
          ),
          ListTile(
            key: const Key('clearHistoryTile'),
            leading: const Icon(Icons.history),
            title: const Text('Clear browsing history'),
            subtitle: const Text('Searches and recently viewed items'),
            onTap: () => _clearHistory(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(strings.get('privacy')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showPrivacyInfo(context),
          ),

          const Divider(indent: AppSpacing.md),

          // ── Account management ──────────────────────────────────────
          const _SectionHeader('Account'),
          if (!isGuest)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Edit profile'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/profile/edit'),
            ),
          ListTile(
            key: const Key('settingsLogoutTile'),
            leading: const Icon(Icons.logout),
            title: Text(isGuest ? 'Exit guest mode' : 'Sign out'),
            onTap: () => _confirmSignOut(context, ref, isGuest),
          ),
          if (!isGuest)
            ListTile(
              key: const Key('deleteAccountTile'),
              leading: const Icon(Icons.delete_forever, color: AppColors.error),
              title: const Text(
                'Delete account',
                style: TextStyle(color: AppColors.error),
              ),
              subtitle: const Text('Permanently remove your account'),
              onTap: () => _confirmDeleteAccount(context, ref),
            ),
          const Divider(indent: AppSpacing.md),

          // ── About ───────────────────────────────────────────────────
          ListTile(
            key: const Key('settingsAppTourTile'),
            leading: const Icon(Icons.tour_outlined),
            title: const Text('App tour'),
            subtitle: const Text('See how Hyperlocal works, step by step'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/onboarding'),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Help & Support'),
            subtitle: const Text('FAQ, contact us, report an issue'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/help'),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(strings.get('about')),
            subtitle: const Text('Version 1.0.0'),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }

  String _themeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System default';
    }
  }

  Future<void> _pickLanguage(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(settingsControllerProvider.notifier);
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Select Language'),
        children: [
          SimpleDialogOption(
            key: const Key('langEnOption'),
            onPressed: () => Navigator.pop(dialogContext, 'en'),
            child: const Text('English'),
          ),
          SimpleDialogOption(
            key: const Key('langHiOption'),
            onPressed: () => Navigator.pop(dialogContext, 'hi'),
            child: const Text('हिंदी (Hindi)'),
          ),
        ],
      ),
    );
    if (selected != null) controller.setLanguage(selected);
  }

  Future<void> _pickTheme(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(settingsControllerProvider.notifier);
    final current = ref.read(settingsControllerProvider).themeMode;
    final selected = await showDialog<ThemeMode>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Theme'),
        children: [
          for (final mode in ThemeMode.values)
            SimpleDialogOption(
              key: Key('theme_${mode.name}'),
              onPressed: () => Navigator.pop(dialogContext, mode),
              child: Row(
                children: [
                  Icon(
                    current == mode
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    size: 20,
                    color: current == mode
                        ? AppColors.primary
                        : AppColors.textMuted,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(switch (mode) {
                    ThemeMode.system => 'System default',
                    ThemeMode.light => 'Light',
                    ThemeMode.dark => 'Dark',
                  }),
                ],
              ),
            ),
        ],
      ),
    );
    if (selected != null) controller.setThemeMode(selected);
  }

  Future<void> _clearHistory(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear browsing history?'),
        content: const Text(
          'Your recent searches and recently viewed items on this device '
          'will be removed. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('confirmClearHistory'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final repository = ref.read(savedAndHistoryRepositoryProvider);
    await Future.wait([
      repository.clearRecentSearches(),
      repository.clearRecentlyViewed(),
      repository.clearRecentlyViewedShops(),
    ]);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Browsing history cleared.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showPrivacyInfo(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Privacy & Data',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Hyperlocal stores your saved addresses, favorites and '
              'preferences on this device. Account-backed data is synced '
              'only while you are signed in.\n\n'
              'Analytics are off by default. Clearing browsing history '
              'removes device-local searches and viewed items immediately.',
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmSignOut(
    BuildContext context,
    WidgetRef ref,
    bool isGuest,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isGuest ? 'Exit guest mode?' : 'Sign out?'),
        content: Text(
          isGuest
              ? 'You will return to the sign-in screen.'
              : 'Are you sure you want to sign out of this device?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('confirmSettingsLogout'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }

  Future<void> _confirmDeleteAccount(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently removes your account and synced data from our '
          'servers. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('confirmDeleteAccount'),
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete forever'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final deleted = await ref
        .read(profileControllerProvider.notifier)
        .deleteAccount();
    if (!context.mounted) return;
    if (!deleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not delete your account. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    // Sign out locally after the deletion request.
    await ref.read(authControllerProvider.notifier).logout();
  }
}

/// Uppercase group label used between setting sections.
///
/// Accepts a [key] so callers can anchor a deep-link scroll position to a
/// specific section.
class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}

/// Per-type and per-channel notification switches.
///
/// Reads/writes through [NotificationPreferencesController]; the master
/// device switch above gates whether any of this matters on-device.
class _NotificationPreferencesSection extends ConsumerWidget {
  const _NotificationPreferencesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationPreferencesControllerProvider);
    final controller = ref.read(
      notificationPreferencesControllerProvider.notifier,
    );
    final prefs = state.preferences;

    if (state.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Column(
      children: [
        _prefSwitch(
          key: const Key('prefPriceDrop'),
          icon: Icons.sell_outlined,
          title: 'Price drop alerts',
          value: prefs.priceAlerts,
          onChanged: controller.setPriceAlerts,
        ),
        _prefSwitch(
          key: const Key('prefAvailability'),
          icon: Icons.inventory_2_outlined,
          title: 'Product availability',
          value: prefs.availabilityAlerts,
          onChanged: controller.setAvailabilityAlerts,
        ),
        _prefSwitch(
          key: const Key('prefOffers'),
          icon: Icons.local_offer_outlined,
          title: 'Deal alerts',
          value: prefs.dealAlerts,
          onChanged: controller.setDealAlerts,
        ),
        _prefSwitch(
          key: const Key('prefPromotional'),
          icon: Icons.campaign_outlined,
          title: 'Promotions',
          value: prefs.promotional,
          onChanged: controller.setPromotional,
        ),
        _prefSwitch(
          key: const Key('prefShopUpdates'),
          icon: Icons.storefront_outlined,
          title: 'Shop updates',
          value: prefs.shopUpdates,
          onChanged: controller.setShopUpdates,
        ),
        const Divider(indent: AppSpacing.md),
        _prefSwitch(
          key: const Key('prefEmailChannel'),
          icon: Icons.mail_outline,
          title: 'Email notifications',
          value: prefs.emailEnabled,
          onChanged: controller.setEmail,
        ),
        _prefSwitch(
          key: const Key('prefSmsChannel'),
          icon: Icons.sms_outlined,
          title: 'SMS notifications',
          value: prefs.smsEnabled,
          onChanged: controller.setSms,
        ),
      ],
    );
  }

  Widget _prefSwitch({
    Key? key,
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      key: key,
      secondary: Icon(icon, size: 22, color: AppColors.textMuted),
      title: Text(title, style: const TextStyle(fontSize: 15)),
      dense: true,
      value: value,
      onChanged: onChanged,
    );
  }
}
