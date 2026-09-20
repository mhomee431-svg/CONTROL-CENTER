import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../l10n/app_localizations.dart';
import '../controllers/settings_controller.dart';
import '../widgets/settings_widgets.dart';

/// Device-level app appearance.
///
/// The theme choice is REAL: [SettingsController.setThemeMode] feeds
/// `MaterialApp.router.themeMode`, so tapping a row rethemes the whole app
/// immediately. It is a device preference rather than shop data, which is why
/// signing out leaves it alone.
class AppSettingsScreen extends ConsumerWidget {
  const AppSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final current = ref.watch(settingsControllerProvider).themeMode;
    final controller = ref.read(settingsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.appSettingsTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            SettingsIntro(
              icon: Icons.palette_outlined,
              title: l10n.appSettingsIntroTitle,
              subtitle: l10n.appSettingsIntroSubtitle,
            ),
            SettingsSection(
              title: l10n.appSettingsGroupTheme,
              footnote: l10n.appSettingsThemeFootnote,
              children: [
                for (final mode in ThemeMode.values)
                  SettingsChoiceTile(
                    key: Key('theme_option_${mode.name}'),
                    icon: _themeIcon(mode),
                    label: themeModeLabel(l10n, mode),
                    description: _themeDescription(l10n, mode),
                    selected: current == mode,
                    onSelect: () => controller.setThemeMode(mode),
                  ),
              ],
            ),
            // Notifications / Privacy policy / About are NOT repeated here:
            // they are rows on the Settings hub (this screen's parent), so a
            // destination lives in exactly one place.
            const SizedBox(height: 24),
            SettingsSection(
              title: l10n.appSettingsGroupLanguage,
              children: [
                SettingsTile(
                  key: const Key('app_settings_language'),
                  icon: Icons.language_outlined,
                  title: l10n.appSettingsLanguageLink,
                  // The current choice, straight from the shared controller —
                  // the Language screen owns the explanation of what is
                  // available, so the two never state it differently.
                  subtitle: ref.watch(settingsControllerProvider).language.label,
                  onTap: () => context.push(Routes.language),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

IconData _themeIcon(ThemeMode mode) => switch (mode) {
      ThemeMode.system => Icons.brightness_auto_outlined,
      ThemeMode.light => Icons.light_mode_outlined,
      ThemeMode.dark => Icons.dark_mode_outlined,
    };

String _themeDescription(AppLocalizations l10n, ThemeMode mode) => switch (mode) {
      ThemeMode.system => l10n.themeFollowDeviceDescription,
      ThemeMode.light => l10n.themeLightDescription,
      ThemeMode.dark => l10n.themeDarkDescription,
    };

// The selectable rows are [SettingsChoiceTile] (settings_widgets.dart) — the
// same widget the Language picker uses, so a "selected" state cannot drift.