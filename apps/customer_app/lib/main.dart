import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/env/env_config.dart';
import 'core/security/safe_logger.dart';
import 'features/notifications/data/fcm_notification_service.dart';
import 'features/search/data/discovery_lexicon_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase must be ready before any auth or FCM call. In mock mode (no API
  // base URL configured) auth uses FakePhoneAuthService, so we skip init.
  if (EnvConfig.hasApiBaseUrl) {
    await Firebase.initializeApp();
    registerFcmBackgroundHandler();
  }

  // ── Phase 14: production API guard ─────────────────────────────────────
  // Fail fast if a release build is misconfigured (http://, empty, or
  // relative base URL) instead of silently shipping against a bad backend.
  EnvConfig.validateProduction();

  // ── Phase 12: crash handling foundation ────────────────────────────
  // Route uncaught framework/platform errors through SafeLogger (redacted
  // in debug, suppressed in release). A remote reporter (Sentry/Crashlytics)
  // can attach here in a later phase.
  FlutterError.onError = (details) {
    SafeLogger.error(
      'Uncaught framework error',
      details.exception,
      details.stack,
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    SafeLogger.error('Uncaught platform error', error, stack);
    return true; // Handled — do not kill the isolate silently.
  };

  // The container is created explicitly rather than inside an inline
  // `const ProviderScope`, because the discovery warm-up below needs to read a
  // provider from the same container the widget tree will use.
  final container = ProviderContainer();
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const HyperlocalApp(),
    ),
  );

  // ── Product discovery vocabulary ────────────────────────────────────────
  // Warmed ONCE here, deliberately after the first frame: `discoveryLexiconProvider`
  // is read on every search keystroke and must stay a pure, synchronous read, so
  // these fetches are explicit startup side effects rather than something
  // searching can trigger.
  //
  // Both are strictly an improvement on having no vocabulary. Until a warm-up
  // lands (or if one fails), a brand or category query falls back to a text
  // search, which still returns the right products because the backend's index
  // matches brand and category text.
  unawaited(container.read(brandVocabularyWarmupProvider.future));
  unawaited(container.read(categoryVocabularyWarmupProvider.future));
}
