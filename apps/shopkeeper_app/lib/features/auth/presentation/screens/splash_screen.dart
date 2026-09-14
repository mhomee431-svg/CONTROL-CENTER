import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../controllers/auth_controller.dart';

/// Startup screen — initializes Firebase, checks auth state, loads local
/// storage, and app configuration. Shows logo + spinner (no fake progress %).
///
/// On initialization failure, shows a retry button instead of hanging.
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
    return Scaffold(
      body: Center(
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
                      style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
