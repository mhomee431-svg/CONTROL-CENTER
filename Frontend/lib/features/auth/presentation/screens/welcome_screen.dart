import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../controllers/auth_controller.dart';

/// Welcome/onboarding entry screen shown to first-time users.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.storefront, size: 80, color: AppColors.primary),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Discover Local, Shop Local',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Find nearby stores, compare prices, and get the best deals delivered to your doorstep.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textMuted,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),
              ElevatedButton(
                onPressed: () => context.push('/login'),
                child: const Text('Login with Phone'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: () => ref
                    .read(authControllerProvider.notifier)
                    .continueAsGuest(),
                child: const Text('Continue as Guest'),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: () => context.push('/onboarding-flow'),
                icon: const Icon(Icons.timeline, size: 18),
                label: const Text('View Customer Journey Flow'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}