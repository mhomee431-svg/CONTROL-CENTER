import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
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
    final current = ref.watch(settingsControllerProvider).themeMode;
    final controller = ref.read(settingsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('App settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const SettingsIntro(
              icon: Icons.palette_outlined,
              title: 'Appearance',
              subtitle: 'Applies to this device only',
            ),
            SettingsSection(
              title: 'Theme',
              footnote: 'Kept on this device and left unchanged when you log out.',
              children: [
                _ThemeOption(
                  mode: ThemeMode.system,
                  icon: Icons.brightness_auto_outlined,
                  label: 'Follow device',
                  description: 'Switch with your phone\'s light / dark setting',
                  selected: current == ThemeMode.system,
                  onSelect: () => controller.setThemeMode(ThemeMode.system),
                ),
                _ThemeOption(
                  mode: ThemeMode.light,
                  icon: Icons.light_mode_outlined,
                  label: 'Light',
                  description: 'Always use the light theme',
                  selected: current == ThemeMode.light,
                  onSelect: () => controller.setThemeMode(ThemeMode.light),
                ),
                _ThemeOption(
                  mode: ThemeMode.dark,
                  icon: Icons.dark_mode_outlined,
                  label: 'Dark',
                  description: 'Always use the dark theme',
                  selected: current == ThemeMode.dark,
                  onSelect: () => controller.setThemeMode(ThemeMode.dark),
                ),
              ],
            ),
            SettingsSection(
              title: 'Related settings',
              children: [
                SettingsTile(
                  icon: Icons.notifications_outlined,
                  title: 'Notification settings',
                  subtitle: 'Alert delivery and permissions',
                  onTap: () => context.push(Routes.notificationSettings),
                ),
                SettingsTile(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy policy',
                  onTap: () => context.push(Routes.privacy),
                ),
                SettingsTile(
                  icon: Icons.info_outline,
                  title: 'About this app',
                  onTap: () => context.push(Routes.about),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const SettingsNotice(
              icon: Icons.language_outlined,
              title: 'Language',
              message: 'The shopkeeper app ships in English only for now. '
                  'More languages will be added in a future release.',
            ),
          ],
        ),
      ),
    );
  }
}

/// One selectable theme row.
class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.mode,
    required this.icon,
    required this.label,
    required this.description,
    required this.selected,
    required this.onSelect,
  });

  final ThemeMode mode;
  final IconData icon;
  final String label;
  final String description;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      key: Key('theme_option_${mode.name}'),
      leading: Icon(icon),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      subtitle: Text(description, style: const TextStyle(fontSize: 12)),
      trailing: Icon(
        selected ? Icons.check_circle : Icons.circle_outlined,
        color: selected ? scheme.primary : scheme.outline,
      ),
      onTap: onSelect,
    );
  }
}