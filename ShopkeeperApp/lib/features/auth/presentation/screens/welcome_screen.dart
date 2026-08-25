import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../controllers/auth_controller.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoading = ref.watch(
        authControllerProvider.select((s) => s.isLoading));
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              CircleAvatar(
                radius: 44,
                backgroundColor: AppTheme.brandSeed,
                child: const Icon(Icons.storefront,
                    color: Colors.white, size: 44),
              ),
              const SizedBox(height: 20),
              Text(
                'Run your shop,\nright from your pocket.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Manage products, inventory and offers for every store you own.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
              const Spacer(flex: 3),
              FilledButton(
                onPressed:
                    isLoading ? null : () => context.push('/login'),
                child: const Text('Sign in'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed:
                    isLoading ? null : () => context.push('/register'),
                child: const Text('Create a business account'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
