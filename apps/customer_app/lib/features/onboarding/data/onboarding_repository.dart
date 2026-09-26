import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/local_storage_driver.dart';
import '../../../core/storage/secure_storage_service.dart';

/// Persistence for the one-time onboarding tour.
///
/// The completed flag lives in the existing non-secret local preferences
/// driver so signing out (which clears secure auth storage) does not replay
/// onboarding. The secure key is retained as a read-only migration fallback
/// for customers who completed onboarding before this repository existed.
class OnboardingRepository {
  static const storageKey = 'has_completed_onboarding';
  static const _legacyStorageKey = 'has_onboarded';

  final LocalStorageDriver _localStorage;
  final SecureStorageService _secureStorage;

  const OnboardingRepository(this._localStorage, this._secureStorage);

  Future<bool> hasCompletedOnboarding() async {
    final storedValue = await _localStorage.getString(storageKey);
    if (storedValue == 'true') return true;

    // Upgrade path for versions that persisted onboarding beside auth data.
    return await _secureStorage.read(key: _legacyStorageKey) == 'true';
  }

  Future<void> markOnboardingComplete() =>
      _localStorage.setString(storageKey, 'true');
}

final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  return OnboardingRepository(
    ref.watch(localStorageDriverProvider),
    ref.watch(secureStorageProvider),
  );
});
