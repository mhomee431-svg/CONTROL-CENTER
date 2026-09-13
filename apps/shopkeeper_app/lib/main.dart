import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/env_config.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase must be initialized before any Firebase auth call (Google
  // Sign-In). Options come from the platform config (Android native file or
  // the web/desktop constants in firebase_options.dart).
  await Firebase.initializeApp(options: AppFirebaseOptions.currentPlatform);

  // ── Startup diagnostics: log the EXACT API URL the app will use ────────
  // This catches the classic "flutter run without dart-define" mistake that
  // embeds the emulator-only 10.0.2.2 URL into a physical-device build.
  debugPrint('════════════════════════════════════════════════');
  debugPrint('[STARTUP] API Base URL : ${EnvConfig.apiBaseUrl}');
  debugPrint('[STARTUP] Environment  : ${EnvConfig.environment}');
  debugPrint('════════════════════════════════════════════════');

  // ── Phase 14: production API guard ─────────────────────────────────────
  // Fail fast if a release build is misconfigured (http://, empty, or
  // relative base URL) instead of silently shipping against a bad backend.
  EnvConfig.validateProduction();
  FlutterError.onError = (details) {
    // Release-safe crash logging foundation (remote reporter pending).
    debugPrint('Uncaught framework error: ${details.exception}');
  };
  runApp(const ProviderScope(child: ShopkeeperApp()));
}


