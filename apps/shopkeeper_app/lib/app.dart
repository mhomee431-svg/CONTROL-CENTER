import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/ui/text_scale.dart';
import 'features/account/presentation/controllers/settings_controller.dart';
import 'l10n/app_localizations.dart';

/// Root widget of the Hyperlocal Shopkeeper App.
class ShopkeeperApp extends ConsumerWidget {
  const ShopkeeperApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final settings = ref.watch(settingsControllerProvider);
    return MaterialApp.router(
      // `onGenerateTitle` rather than `title`: the task-switcher label comes
      // from the arb too, and `title` has no Localizations scope to read from.
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      // Localization architecture (see l10n/README.md): every user-facing
      // string comes from `lib/l10n/app_en.arb` through [AppLocalizations], and
      // the locale follows the Language setting instead of being hardcoded.
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLanguage.supportedLocales,
      locale: Locale(settings.language.code),
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode,
      // Font-scaling policy — see [TextScalePolicy]. The platform setting is
      // honoured up to the ceiling the layouts are built for, so large-text
      // users get bigger text without clipping chips, badges or CTAs.
      builder: (context, child) =>
          TextScalePolicy.apply(child ?? const SizedBox.shrink()),
      routerConfig: router,
    );
  }
}
