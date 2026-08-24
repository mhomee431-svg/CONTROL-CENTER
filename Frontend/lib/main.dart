import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/security/safe_logger.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

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