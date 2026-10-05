import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/env/env_config.dart';
import 'core/observability/crash_reporter.dart';
import 'core/observability/performance_observer.dart';
import 'core/security/safe_logger.dart';
import 'features/notifications/data/fcm_notification_service.dart';
import 'features/search/data/discovery_lexicon_provider.dart';

Future<void> main() async {
  // Captured before ANY other work so the number means "time to usable app",
  // not "time to the rest of main()". Everything below — binding init, Firebase,
  // env validation — is inside the measurement, which is the point: those are
  // the things that actually make startup slow.
  final startupClock = Stopwatch()..start();

  WidgetsFlutterBinding.ensureInitialized();

  // ── Observability ────────────────────────────────────────────────────────
  // Installed before anything that can fail, so a crash during startup is
  // still captured. Uses only Flutter/Dart built-ins — no third-party SDK.
  //
  // Frame timings are hooked here rather than after `runApp` because the first
  // frames are exactly the ones worth measuring.
  PerformanceObserver.instance.hookFrameTimings();
  CrashReporter().install();

  // Firebase must be ready before any auth or FCM call. In mock mode (no API
  // base URL configured) auth uses FakePhoneAuthService, so we skip init.
  //
  // Failures are handled explicitly rather than allowed to propagate. An
  // uncaught throw here kills the app BEFORE `runApp`, which on iOS — where no
  // GoogleService-Info.plist and no lib/firebase_options.dart are committed —
  // means a blank screen and no explanation. Swallowing it lets the app start on
  // the fake-auth path instead, with the reason recorded where it can be found.
  if (EnvConfig.hasApiBaseUrl) {
    try {
      await Firebase.initializeApp();
      registerFcmBackgroundHandler();
    } catch (error, stack) {
      CrashReporter().capture(error, stack, source: 'firebase_init');
      SafeLogger.error(
        'Firebase.initializeApp failed. The app will continue with fake auth, '
        'so sign-in and OTP will not work. On Android check that '
        'android/app/google-services.json exists and its package_name matches '
        'applicationId in android/app/build.gradle.kts. On iOS this additionally '
        'needs ios/Runner/GoogleService-Info.plist, which is NOT committed — add '
        'the Firebase iOS app in the Console and place the plist there, or '
        'generate lib/firebase_options.dart with `flutterfire configure`.',
      );
    }
  }

  // ── Phase 14: production API guard ─────────────────────────────────────
  // Fail fast if a release build is misconfigured (http://, empty, or
  // relative base URL) instead of silently shipping against a bad backend.
  EnvConfig.validateProduction();

  // ── Crash handling ──────────────────────────────────────────────────────
  // Installed above via `CrashReporter().install()`, which captures both the
  // framework and platform handlers AND writes to SafeLogger, so debug console
  // behaviour is unchanged. Deliberately NOT re-declared here: a second
  // assignment would silently replace the reporter with a logger and the app
  // would go back to leaving no trace in release.

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

  // "Startup" means until something is on screen, not until `runApp` returns.
  // `runApp` schedules the first frame and returns immediately, so stopping the
  // clock here would report a number that excludes the entire first render —
  // which on a cold start is often the slowest part.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    startupClock.stop();
    PerformanceObserver.instance.record(
      'app_startup',
      startupClock.elapsed,
      data: {'first_frame_ms': startupClock.elapsedMilliseconds},
    );
  });

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
