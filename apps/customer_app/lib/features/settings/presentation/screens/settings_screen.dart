import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../auth/domain/auth_service.dart' show authAppVersion;
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../notifications/presentation/controllers/notification_preferences_controller.dart';
import '../../../profile/presentation/controllers/profile_controller.dart';
import '../../../saved_and_history/domain/saved_and_history_repository.dart';
import '../../../saved_and_history/presentation/controllers/saved_and_history_controllers.dart';
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
          // -- Account --
          // Identity links live at the top: they are the most common reason
          // someone opens Settings, and the account hub is now the single
          // place for profile / saved items / addresses / notifications.
          const _SectionHeader('Account'),
          ListTile(
            key: const Key('settingsAccountHubTile'),
            leading: const Icon(Icons.account_circle_outlined),
            title: const Text('My account'),
            subtitle: const Text('Profile, saved items and notifications'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/account'),
          ),
          if (!isGuest)
            ListTile(
              key: const Key('settingsEditProfileTile'),
              leading: const Icon(Icons.person_outline),
              title: const Text('Edit profile'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/profile/edit'),
            ),
          const Divider(indent: AppSpacing.md),

          // -- Notifications --
          // The switches now live on a dedicated screen, so this row is a
          // pointer rather than a summary that would drift out of sync with
          // it. Keeping one home for the toggles means the account-wide
          // matrix can only be described in one place.
          _SectionHeader('Notifications', key: _notificationsKey),
          ListTile(
            key: const Key('notificationSettingsTile'),
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notification settings'),
            subtitle: Text(
              settings.pushNotificationsEnabled
                  ? 'Price, availability and offer alerts'
                  : 'Push alerts are off on this device',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/notification-settings'),
          ),
          const Divider(indent: AppSpacing.md),

          // -- Location --
          const _SectionHeader('Location preferences'),
          SwitchListTile(
            secondary: const Icon(Icons.location_on),
            title: Text(strings.get('locationServices')),
            subtitle: const Text('Use GPS to find nearby shops'),
            value: settings.locationEnabled,
            onChanged: controller.toggleLocation,
          ),
          ListTile(
            key: const Key('locationSettingsTile'),
            leading: const Icon(Icons.my_location),
            title: const Text('Location settings'),
            subtitle: const Text(
              'Current location, default address and permission',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/location-settings'),
          ),
          ListTile(
            leading: const Icon(Icons.bookmark_border),
            title: const Text('Default address'),
            subtitle: const Text('Manage saved addresses'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/profile/addresses'),
          ),
          const Divider(indent: AppSpacing.md),

          // -- Appearance --
          // "Appearance" rather than "Theme": the customer is choosing how
          // the app looks to them, not picking an implementation detail.
          const _SectionHeader('Appearance'),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Theme'),
            subtitle: Text(_themeLabel(settings.themeMode)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickTheme(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(strings.get('language')),
            subtitle: Text(
              settings.languageCode == 'en' ? 'English' : 'हिन्दी',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickLanguage(context, ref),
          ),
          const Divider(indent: AppSpacing.md),

          // -- Privacy --
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
            key: const Key('clearAllLocalDataTile'),
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('Clear all local data'),
            subtitle: const Text('Also removes saved products and shops'),
            onTap: () => _clearAllLocalData(context, ref),
          ),
          ListTile(
            key: const Key('privacyPolicyTile'),
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy & data'),
            subtitle: const Text(
              'What we collect, location use and your controls',
            ),
            trailing: const Icon(Icons.chevron_right),
            // The interactive centre. The legal policy document is one tap
            // deeper from there, rather than duplicating it here.
            onTap: () => context.push('/privacy-data'),
          ),

          const Divider(indent: AppSpacing.md),

          // -- Support --
          const _SectionHeader('Support & About'),
          ListTile(
            key: const Key('settingsHelpTile'),
            leading: const Icon(Icons.help_outline),
            title: const Text('Help & Support'),
            subtitle: const Text('FAQ, contact us, report an issue'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/help'),
          ),
          ListTile(
            key: const Key('settingsTermsTile'),
            leading: const Icon(Icons.gavel_outlined),
            title: const Text('Terms of Service'),
            subtitle: const Text('Rules for using Hyperlocal'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/terms'),
          ),
          ListTile(
            key: const Key('settingsAppTourTile'),
            leading: const Icon(Icons.tour_outlined),
            title: const Text('App tour'),
            subtitle: const Text('See how Hyperlocal works, step by step'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/onboarding'),
          ),
          ListTile(
            key: const Key('settingsAboutTile'),
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            subtitle: Text('Version $authAppVersion'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/about'),
          ),
          const Divider(indent: AppSpacing.md),

          // -- Session --
          const _SectionHeader('Session'),
          ListTile(
            key: const Key('settingsLogoutTile'),
            leading: const Icon(Icons.logout),
            title: Text(isGuest ? 'Exit guest mode' : 'Sign out'),
            subtitle: const Text('Sign out of your account on this device'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _confirmSignOut(context, ref, isGuest),
          ),

          // Deleting an account is irreversible and is backed by a real
          // endpoint (DELETE /users/me, API contract §7.3), so it earns its
          // own "Danger zone" at the very bottom rather than sitting next to
          // the ordinary sign-out row where a stray tap could destroy data.
          if (!isGuest) ...[
            const SizedBox(height: AppSpacing.sm),
            const _SectionHeader('Danger zone'),
            ListTile(
              key: const Key('deleteAccountTile'),
              leading: const Icon(
                Icons.delete_forever,
                color: AppColors.error,
              ),
              title: const Text(
                'Delete account',
                style: TextStyle(color: AppColors.error),
              ),
              subtitle: const Text(
                'Permanently remove your account and synced data',
              ),
              trailing: const Icon(
                Icons.chevron_right,
                color: AppColors.error,
              ),
              // The full flow lives on its own screen: impact, confirmation,
              // the real backend call, then session teardown.
              onTap: () => context.push('/delete-account'),
            ),
          ],
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
            child: const Text('हिन्दी (Hindi)'),
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

  /// Wipes every piece of device-local personalization, saved items included.
  ///
  /// Deliberately broader than [_clearHistory]: that only drops searches and
  /// recently viewed items, which left saved products and shops impossible to
  /// remove from the device. Both are device-local; the backend copy is only
  /// touched when the customer signs in, so this must say so plainly.
  Future<void> _clearAllLocalData(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear all local data?'),
        content: const Text(
          'This removes your saved products, saved shops, recent searches '
          'and recently viewed items from this device.\n\n'
          'Items already synced to your account stay on your account, but '
          'this device will have to download them again. This cannot be '
          'undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('confirmClearAllLocalData'),
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Clear everything'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final repository = ref.read(savedAndHistoryRepositoryProvider);
    // Every clear is independent: one failure must not abandon the rest, so
    // they are run concurrently and each one's own error is swallowed by the
    // repository contract (these are idempotent best-effort calls).
    await Future.wait([
      repository.clearRecentSearches(),
      repository.clearRecentlyViewed(),
      repository.clearRecentlyViewedShops(),
      repository.clearSavedProducts(),
      repository.clearSavedShops(),
    ]);

    if (!context.mounted) return;
    // Refresh the visible lists so the change is not a lie on screen.
    ref.invalidate(savedProductsNotifierProvider);
    ref.invalidate(savedShopsNotifierProvider);
    ref.invalidate(recentSearchesNotifierProvider);
    ref.invalidate(recentlyViewedNotifierProvider);
    ref.invalidate(recentlyViewedShopsNotifierProvider);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('All local data cleared.'),
        behavior: SnackBarBehavior.floating,
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
