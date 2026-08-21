import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/settings_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final strings = ref.watch(appStringsProvider);
    final controller = ref.read(settingsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(strings.get('settingsTitle'))),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(strings.get('language')),
            subtitle: Text(settings.languageCode == 'en' ? 'English' : 'हिंदी'),
            onTap: () {
              showDialog(
                context: context,
                builder: (ctx) => SimpleDialog(
                  title: const Text('Select Language'),
                  children: [
                    SimpleDialogOption(
                      onPressed: () {
                        controller.setLanguage('en');
                        Navigator.pop(ctx);
                      },
                      child: const Text('English'),
                    ),
                    SimpleDialogOption(
                      onPressed: () {
                        controller.setLanguage('hi');
                        Navigator.pop(ctx);
                      },
                      child: const Text('हिंदी (Hindi)'),
                    ),
                  ],
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.brightness_6),
            title: Text(strings.get('theme')),
            subtitle: Text(settings.themeMode.name.toUpperCase()),
            onTap: () {
              final nextMode = settings.themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
              controller.setThemeMode(nextMode);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active),
            title: Text(strings.get('pushNotifications')),
            value: settings.pushNotificationsEnabled,
            onChanged: controller.toggleNotifications,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.location_on),
            title: Text(strings.get('locationServices')),
            value: settings.locationEnabled,
            onChanged: controller.toggleLocation,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(strings.get('privacy')),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: Text(strings.get('helpSupport')),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(strings.get('about')),
            subtitle: const Text('Version 1.0.0'),
          ),
        ],
      ),
    );
  }
}