import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/presentation/controllers/auth_controller.dart';
import '../location/presentation/controllers/location_controller.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Check auth status on startup; the router redirect will handle navigation
    Future.microtask(() {
      ref.read(authControllerProvider.notifier).checkAuthStatus();
            // Auto-detect location on app start (force: true to bypass throttle)
      ref.read(locationControllerProvider.notifier).fetchCurrentLocation(force: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Hyperlocal',
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}