import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/env_config.dart';
import 'features/auth/data/auth_repository.dart' show kUseMockAuth;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase must be ready before any auth call. In mock mode Firebase is
  // bypassed entirely (FakePhoneAuthService) so we skip initialization.
  if (!kUseMockAuth) {
    await Firebase.initializeApp();
  }

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
