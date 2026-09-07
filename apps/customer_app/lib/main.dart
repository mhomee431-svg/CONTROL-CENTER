import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/env/env_config.dart';
import 'core/security/safe_logger.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

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

  runApp(const ProviderScope(child: HyperlocalApp()));
}