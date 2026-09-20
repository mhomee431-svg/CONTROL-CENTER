import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../notifications/domain/notification_models.dart';
import '../../../notifications/presentation/controllers/notification_preferences_controller.dart';
import '../controllers/settings_controller.dart';
import '../widgets/settings_widgets.dart';

/// What Passly keeps on this device, plus the one reset that is genuinely local.
///
/// Deliberately specific: the app holds NO offline copy of products, stock or
/// alerts (every screen reads the backend), so there is no big "Clear cache"
/// button pretending to free space. The real, useful action is resetting the
/// delivery preferences saved on this device.
class DataStorageScreen extends ConsumerStatefulWidget {
  const DataStorageScreen({super.key});

  @override
  ConsumerState<DataStorageScreen> createState() => _DataStorageScreenState();
}

class _DataStorageScreenState extends ConsumerState<DataStorageScreen> {
  bool _resetting = false;

  @override
  void initState() {
    super.initState();
    // Load the saved preferences so "Saved" vs "Using the defaults" below is
    // the truth rather than a guess.
    Future.microtask(
        () => ref.read(notificationPreferencesProvider.notifier).load());
  }

  Future<void> _resetPreferences() async {
    // Resolved BEFORE the await: `context` must not be used across an await,
    // and the copy is needed after the dialog closes.
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.dataStorageResetDialogTitle),
        content: Text(l10n.dataStorageResetDialogContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const Key('confirm_reset_preferences'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.dataStorageResetAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _resetting = true);
    final ok = await ref
        .read(notificationPreferencesProvider.notifier)
        .clearSaved();
    if (!mounted) return;
    setState(() => _resetting = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? l10n.dataStorageResetSuccess
                : l10n.dataStorageResetFailure,
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsControllerProvider);
    final preferences = ref.watch(notificationPreferencesProvider).saved;
    final usingDefaults = preferences == const NotificationPreferences();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.dataStorageTitle)),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xl),
          children: [
            SettingsIntro(
              icon: Icons.storage_outlined,
              title: l10n.dataStorageIntroTitle,
              subtitle: l10n.dataStorageIntroSubtitle,
            ),
            SettingsSection(
              title: l10n.dataStorageGroupStored,
              children: [
                SettingsTile(
                  icon: Icons.lock_outline,
                  title: l10n.dataStorageTokens,
                  subtitle: l10n.dataStorageTokensSubtitle,
                  trailingLabel: l10n.dataStorageEncrypted,
                ),
                SettingsTile(
                  key: const Key('data_storage_preferences'),
                  icon: Icons.tune,
                  title: l10n.dataStoragePreferences,
                  subtitle: usingDefaults
                      ? l10n.dataStorageUsingDefaults
                      : l10n.dataStorageSavedForAccount,
                  trailingLabel:
                      usingDefaults ? l10n.dataStorageDefaults : l10n.dataStorageSaved,
                ),
                SettingsTile(
                  icon: Icons.palette_outlined,
                  title: l10n.dataStorageAppearance,
                  subtitle: l10n.dataStorageAppearanceSubtitle(
                    themeModeLabel(l10n, settings.themeMode),
                    settings.language.label,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('data_storage_reset_preferences'),
              onPressed: _resetting ? null : _resetPreferences,
              icon: _resetting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.restart_alt),
              label: Text(
                _resetting
                    ? l10n.dataStorageResetting
                    : l10n.dataStorageResetPreferences,
              ),
            ),
            const SizedBox(height: 24),
            SettingsSection(
              title: l10n.dataStorageGroupDevice,
              children: [
                SettingsTile(
                  key: const Key('data_storage_sessions'),
                  icon: Icons.devices_outlined,
                  title: l10n.settingsSessionsDevices,
                  subtitle: l10n.dataStorageSessionsSubtitle,
                  onTap: () => context.push(Routes.sessions),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SettingsNotice(
              icon: Icons.cloud_done_outlined,
              title: l10n.dataStorageNothingOfflineTitle,
              message: l10n.dataStorageNothingOfflineMessage,
            ),
          ],
        ),
      ),
    );
  }
}
