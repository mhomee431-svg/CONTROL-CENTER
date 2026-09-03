import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/env_config.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

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
