import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../controllers/settings_controller.dart';
import '../widgets/settings_widgets.dart';

/// App language picker.
///
/// Only English is bundled in this release, so English is the ONE selectable
/// row; the planned languages are listed with a "Coming soon" label instead of
/// a switch that would silently keep rendering English. Selecting a language
/// goes through [SettingsController.setLanguage], which refuses anything whose
/// strings are not bundled.
class LanguageScreen extends ConsumerWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final current = ref.watch(settingsControllerProvider).language;
    final controller = ref.read(settingsControllerProvider.notifier);

    final available =
        AppLanguage.values.where((language) => language.isAvailable);
    final pending =
        AppLanguage.values.where((language) => !language.isAvailable);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.languageTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            SettingsIntro(
              icon: Icons.language_outlined,
              title: l10n.languageIntroTitle,
              subtitle: l10n.languageIntroSubtitle,
            ),
            SettingsSection(
              title: l10n.languageGroupAvailable,
              footnote: l10n.languageFootnote,
              children: [
                for (final language in available)
                  SettingsChoiceTile(
                    key: Key('language_option_${language.code}'),
                    icon: Icons.translate_outlined,
                    label: language.label,
                    description: language == current
                        ? l10n.languageCurrentDescription
                        : l10n.languageUseDescription(language.label),
                    selected: language == current,
                    onSelect: () => controller.setLanguage(language),
                  ),
              ],
            ),
            SettingsSection(
              title: l10n.languageGroupComingSoon,
              children: [
                for (final language in pending)
                  SettingsTile(
                    key: Key('language_pending_${language.code}'),
                    icon: Icons.hourglass_empty,
                    title: language.label,
                    subtitle: l10n.languageNotTranslated,
                    trailingLabel: l10n.languageComingSoon,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SettingsNotice(
              icon: Icons.phone_iphone_outlined,
              title: l10n.languagePhoneNoticeTitle,
              message: l10n.languagePhoneNoticeMessage,
            ),
          ],
        ),
      ),
    );
  }
}