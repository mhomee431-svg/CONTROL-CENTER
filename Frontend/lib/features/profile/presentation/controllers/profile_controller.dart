import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_client.dart';
import '../../data/api_profile_repository.dart';
import '../../domain/models/user_profile.dart';

final profileControllerProvider = NotifierProvider<ProfileController, UserProfile?>(
  ProfileController.new,
);

class ProfileController extends Notifier<UserProfile?> {
  ApiProfileRepository? _repository;

  @override
  UserProfile? build() {
    _repository = ApiProfileRepository(ref.watch(apiClientProvider));
    _loadProfile();
    return null;
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _repository!.getProfile();
      state = profile;
    } catch (_) {
      // If not authenticated, keep null so the UI shows the login prompt.
      state = null;
    }
  }

  Future<void> updateProfile({
    required String name,
    required String email,
    required String phoneNumber,
  }) async {
    try {
      final updated = await _repository!.updateProfile(
        name: name,
        email: email,
        phoneNumber: phoneNumber,
      );
      state = updated;
    } catch (_) {
      // Keep current state on failure
    }
  }

  void logout() {
    state = null; // Triggers auth state cascade
  }
}