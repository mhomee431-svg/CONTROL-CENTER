import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/onboarding_repository.dart';

/// One-time onboarding tour state.
///
/// `null` = still loading from storage (router holds on `/splash`).
/// `false` = first launch, show `/onboarding` once.
/// `true` = tour completed or skipped, never show again.
final onboardingCompletedProvider =
    NotifierProvider<OnboardingCompletedController, bool?>(
      OnboardingCompletedController.new,
    );

class OnboardingCompletedController extends Notifier<bool?> {
  @override
  bool? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    try {
      final completed = await ref
          .read(onboardingRepositoryProvider)
          .hasCompletedOnboarding();
      state = completed;
    } catch (_) {
      // Storage must never block first launch: if unreadable, show the tour
      // once rather than trapping the customer on splash.
      state = false;
    }
  }

  /// Persist completion (tour finished or explicitly skipped) and update the
  /// router gate immediately.
  Future<void> completeOnboarding() async {
    try {
      await ref.read(onboardingRepositoryProvider).markOnboardingComplete();
    } catch (_) {
      // Best-effort persistence — the in-memory flag still unblocks routing.
    }
    state = true;
  }
}
