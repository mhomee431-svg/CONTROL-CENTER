import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/account/presentation/controllers/settings_controller.dart';

/// Root widget of the Hyperlocal Shopkeeper App.
class ShopkeeperApp extends ConsumerWidget {
  const ShopkeeperApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    // Theme choice lives in SettingsController so the *App settings* screen can
    // actually retheme the app (default stays "follow the device").
    final themeMode = ref.watch(settingsControllerProvider).themeMode;
    return MaterialApp.router(
      title: 'Hyperlocal Shopkeeper',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
