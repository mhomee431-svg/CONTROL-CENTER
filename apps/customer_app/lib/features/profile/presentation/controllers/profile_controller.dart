import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../../core/security/safe_logger.dart';
import '../../domain/models/user_profile.dart';
import '../../domain/profile_repository.dart';

final profileControllerProvider =
    AsyncNotifierProvider<ProfileController, UserProfile?>(
      ProfileController.new,
    );

class ProfileController extends AsyncNotifier<UserProfile?> {
  @override
  Future<UserProfile?> build() async {
    // Only signed-in customers own a server profile; guests and
    // signed-out users get a null profile (the screen shows the guest
    // UI based on the auth state).
    final authStatus = ref.watch(authControllerProvider).status;
    if (authStatus != AuthStatus.authenticated) {
      return null;
    }
    // A profile fetch that throws is deliberately swallowed into a null
    // profile. Letting the error escape `build()` would hand it to Riverpod's
    // automatic retry, which reschedules with backoff for as long as the
    // provider is alive — an unreachable profile endpoint would then retry
    // forever, holding a live timer and hammering the API. The account and
    // profile screens both render a sensible degraded state for a null
    // profile, and `refresh()` is the explicit, user-driven retry.
    try {
      // Watch (not read) so auth transitions swap repositories automatically.
      return await ref.watch(profileRepositoryProvider).getProfile();
    } catch (error, stackTrace) {
      SafeLogger.error(
        'Profile fetch failed; continuing with a null profile.',
        error,
        stackTrace,
      );
      return null;
    }
  }

  /// Applies edits to the profile. Returns whether it succeeded so the
  /// edit screen can surface success/error feedback.
  Future<bool> updateProfile({
    required String name,
    required String email,
    required String phoneNumber,
  }) async {
    try {
      final repository = ref.read(profileRepositoryProvider);
      final updated = await repository.updateProfile(
        name: name,
        email: email,
        phoneNumber: phoneNumber,
      );
      state = AsyncData(updated);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Requests account deletion through the repository, then clears the
  /// local profile state. The caller signs the user out afterwards.
  Future<bool> deleteAccount() async {
    try {
      await ref.read(profileRepositoryProvider).deleteAccount();
      state = const AsyncData(null);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Reloads the profile after a failed load (error-state retry).
  Future<void> refresh() async {
    state = const AsyncLoading();
    try {
      final repository = ref.read(profileRepositoryProvider);
      state = AsyncData(await repository.getProfile());
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }
}
