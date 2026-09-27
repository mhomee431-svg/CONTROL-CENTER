import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/dev_backend_discovery.dart';
import 'core/config/env_config.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase must be initialized before any Firebase auth call (Google
  // Sign-In). Options come from the platform config (Android native file or
  // the web/desktop constants in firebase_options.dart).
  await Firebase.initializeApp(options: AppFirebaseOptions.currentPlatform);

  // ── Development: auto-discover the reachable backend ────────────────────
  // Plain `flutter run` (no dart-define) embeds the emulator-only 10.0.2.2
  // default, which a physical device can never reach. Probing the known dev
  // candidates (PC LAN IP → adb-reverse → emulator) makes ANY run work.
  // Skipped entirely in production or when an explicit URL is configured.
  if (DevBackendDiscovery.shouldRun) {
    debugPrint('[STARTUP] Discovering dev backend (LAN IP / adb / emulator)...');
    await DevBackendDiscovery.discover();
  }

  // ── Startup diagnostics: log the EXACT API URL the app will use ────────
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

  // ── §111 MEMORY: bound the decoded-image cache explicitly ─────────────────
  // Flutter's defaults (1000 images / 100 MB) are generous for a list app that
  // only ever paints thumbnails. Scrolling a catalog decodes one image per row,
  // so this cache is the largest single consumer of heap in the app; bounding it
  // by BYTES (not just count) is what actually caps the footprint. Set here
  // rather than left to the framework default so the cap is a reviewed number
  // instead of an accident of the SDK.
  PaintingBinding.instance.imageCache
    ..maximumSize = 200
    ..maximumSizeBytes = 32 << 20; // 32 MB

  runApp(const ProviderScope(child: ShopkeeperApp()));
}


