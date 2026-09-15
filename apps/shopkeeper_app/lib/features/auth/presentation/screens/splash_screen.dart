import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../controllers/auth_controller.dart';

/// Startup screen — the router HOLDS this screen while the session state is
/// unknown (`AuthStatus.initial` / `loading`): logo + spinner, no fake
/// progress percentage.
///
/// The startup chain (see [AuthController.checkSession]): stored backend
/// session (`/auth/me`) → device Firebase auth state → fresh ID token →
/// backend exchange (`/firebase-login`) → the guard chain routes accordingly.
///
/// A TRANSIENT failure (offline / backend 5xx) does NOT sign the user out:
/// the splash holds with a Retry button, so there is no Welcome-flicker and
/// a stored session is never lost.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() =>
        ref.read(authControllerProvider.notifier).checkSession());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final auth = ref.watch(authControllerProvider);
    // Startup check failed (offline / backend 5xx): hold the splash with a
    // Retry instead of flicking to Welcome — the session (if any) is kept.
    final startupFailed = auth.status == AuthStatus.sessionError;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // HyperLocal logo + wordmark.
              Image.asset(
                'assets/images/passly_biz_named.png',
                width: 160,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: AppTheme.brandSeed,
                      child: const Icon(Icons.storefront,
                          color: Colors.white, size: 36),
                    ),
                    const SizedBox(height: 16),
                    Text('Hyperlocal Shopkeeper',
                        style: theme.textTheme.titleLarge),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (startupFailed) ...[
                const Icon(Icons.cloud_off, size: 40),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    (auth.errorMessage?.isNotEmpty ?? false)
                        ? auth.errorMessage!
                        : 'Could not complete startup.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14, color: scheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => ref
                      .read(authControllerProvider.notifier)
                      .checkSession(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
                TextButton(
                  onPressed: () => ref
                      .read(authControllerProvider.notifier)
                      .skipStartupRetry(),
                  child: const Text('Sign in instead'),
                ),
              ] else
                const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
