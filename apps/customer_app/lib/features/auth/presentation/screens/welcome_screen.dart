import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../location/presentation/controllers/location_controller.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _WelcomeVisual(),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'HyperLocal',
                    key: const Key('welcomeBrand'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Find Products Nearby',
                    key: const Key('welcomeSubtitle'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton.icon(
                    key: const Key('getStartedButton'),
                    onPressed: () => context.go('/'),
                    icon: const Icon(Icons.explore_outlined),
                    label: const Text('Get Started'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    key: const Key('loginContinueButton'),
                    onPressed: () => context.push('/login'),
                    icon: const Icon(Icons.login_outlined),
                    label: const Text('Login / Continue'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Code-free hero visual combining the three brand ideas: a local shop, the
/// customer's location, and product search.
///
/// Location detection is **opt-in**. Merely opening this screen never prompts
/// for permission — the OS prompt only appears when the customer explicitly
/// taps "Detect my location", where the purpose is unambiguous. If permission
/// is refused the static pin remains and a manual area picker is offered, so
/// the customer is never blocked.
class _WelcomeVisual extends ConsumerWidget {
  const _WelcomeVisual();

  Future<void> _detectLocation(WidgetRef ref) async {
    await ref
        .read(locationControllerProvider.notifier)
        .fetchCurrentLocation(force: true);
    // Deliberately no BuildContext use after the await: the location provider
    // rebuilds this widget, so there is no context-across-async risk.
  }

  /// Best human-readable name for a detected location, or null when unknown.
  String? _detectedLabel(LocationState state) {
    final location = state.location;
    if (state.status != LocationStatus.success || location == null) return null;
    for (final candidate in <String>[
      location.address,
      location.city,
      location.label,
    ]) {
      if (candidate.trim().isNotEmpty) return candidate.trim();
    }
    return 'Current location';
  }

  /// Inline, non-blocking explanation when detection could not complete.
  ///
  /// Written as a switch *expression* so the exhaustiveness check is enforced
  /// by the compiler: adding a new [LocationStatus] becomes a compile error
  /// here rather than a silent fall-through.
  String? _statusMessage(LocationState state) => switch (state.status) {
    LocationStatus.permissionDenied =>
      'Location permission denied. Choose your area to continue.',
    LocationStatus.permissionPermanentlyDenied =>
      'Enable location in device settings, or choose your area.',
    LocationStatus.serviceDisabled =>
      'Location services are off. Turn them on, or choose your area.',
    LocationStatus.error =>
      state.errorMessage ?? 'Could not detect your location.',
    LocationStatus.initial ||
    LocationStatus.loading ||
    LocationStatus.success => null,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(locationControllerProvider);
    final isLoading = state.status == LocationStatus.loading;
    final detectedLabel = _detectedLabel(state);
    final statusMessage = _statusMessage(state);
    final hasDetected = detectedLabel != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: hasDetected
              ? 'A local shop near $detectedLabel, connected to product search'
              : 'A local shop and location pin connected to product search',
          child: SizedBox(
            height: 230,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 210,
                  height: 210,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                ),
                // The pin turns into a "located" state once resolved.
                Positioned(
                  top: 34,
                  left: 82,
                  child: Icon(
                    hasDetected ? Icons.my_location : Icons.location_on,
                    size: 92,
                    color: hasDetected ? AppColors.secondary : AppColors.error,
                  ),
                ),
                const Positioned(
                  top: 76,
                  left: 126,
                  child: Icon(
                    Icons.storefront,
                    size: 96,
                    color: AppColors.primary,
                  ),
                ),
                Align(
                  alignment: const Alignment(0, 0.9),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1A000000),
                          blurRadius: 20,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search, color: AppColors.primary),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            hasDetected
                                ? 'Products near $detectedLabel'
                                : 'Search products near you',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // Opt-in location detection — no permission prompt until tapped.
        if (isLoading)
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator.adaptive(strokeWidth: 2),
              ),
              SizedBox(width: AppSpacing.sm),
              Text('Detecting your location...'),
            ],
          )
        else
          OutlinedButton.icon(
            key: const Key('detectLocationButton'),
            onPressed: () => _detectLocation(ref),
            icon: Icon(
              hasDetected ? Icons.refresh : Icons.my_location,
              size: 18,
            ),
            label: Text(hasDetected ? 'Update location' : 'Detect my location'),
          ),
        if (statusMessage != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            statusMessage,
            key: const Key('detectLocationMessage'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
        if (!hasDetected && !isLoading) ...[
          const SizedBox(height: AppSpacing.xs),
          TextButton(
            key: const Key('chooseAreaManuallyButton'),
            onPressed: () => context.push('/select-location'),
            child: const Text('Choose area manually'),
          ),
        ],
      ],
    );
  }
}
