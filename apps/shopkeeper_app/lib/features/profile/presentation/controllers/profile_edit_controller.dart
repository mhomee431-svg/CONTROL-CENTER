import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../data/profile_repository.dart';

/// State of the Edit-Profile screen.
enum ProfileEditStatus { loading, ready, saving, error }

class ProfileEditState {
  const ProfileEditState({
    this.status = ProfileEditStatus.loading,
    this.name = '',
    this.email,
    this.phoneNumber = '',
    this.error,
    this.saved = false,
  });

  final ProfileEditStatus status;
  final String name;
  final String? email;
  final String phoneNumber;
  final String? error;

  /// One-shot flag: set after a successful save so the screen can navigate
  /// back; reset when the state changes again.
  final bool saved;

  ProfileEditState copyWith({
    ProfileEditStatus? status,
    String? name,
    String? email,
    bool clearEmail = false,
    String? phoneNumber,
    String? error,
    bool clearError = false,
    bool saved = false,
  }) =>
      ProfileEditState(
        status: status ?? this.status,
        name: name ?? this.name,
        email: clearEmail ? null : (email ?? this.email),
        phoneNumber: phoneNumber ?? this.phoneNumber,
        error: clearError ? null : (error ?? this.error),
        saved: saved,
      );
}

class ProfileEditController extends Notifier<ProfileEditState> {
  @override
  ProfileEditState build() {
    Future.microtask(_load);
    return const ProfileEditState();
  }

  ProfileRepository get _repo => ref.read(profileRepositoryProvider);

  Future<void> _load() async {
    // The provider can be disposed while this load is still in flight (the
    // screen was popped, or a test container was torn down). Touching `state`
    // afterwards throws, so every await is followed by a mounted check.
    if (!ref.mounted) return;
    try {
      final profile = await _repo.fetchProfile();
      if (!ref.mounted) return;
      state = ProfileEditState(
        status: ProfileEditStatus.ready,
        name: profile.name ?? '',
        email: profile.email,
        phoneNumber: profile.phoneNumber,
      );
    } on ApiException catch (e) {
      if (!ref.mounted) return;
      state = ProfileEditState(
        status: ProfileEditStatus.error,
        error: e.message.isNotEmpty ? e.message : 'Could not load your profile.',
      );
    } catch (_) {
      if (!ref.mounted) return;
      state = const ProfileEditState(
        status: ProfileEditStatus.error,
        error: 'Could not load your profile. Check your connection.',
      );
    }
  }

  void retry() => state = const ProfileEditState();

  void setName(String v) => state = state.copyWith(name: v);

  void setEmail(String v) =>
      state = state.copyWith(email: v, clearError: true);

  void clearSaved() => state = state.copyWith(saved: false);

  static final RegExp _emailRe =
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Validates and saves. Returns a friendly field error, or null on success
  /// (the [ProfileEditState.saved] flag flips so the UI can navigate back).
  Future<String?> save() async {
    final name = state.name.trim();
    if (name.isEmpty) return 'Name is required';
    if (name.length > 120) return 'Name is too long (max 120 characters)';

    final emailRaw = state.email?.trim() ?? '';
    if (emailRaw.isNotEmpty && !_emailRe.hasMatch(emailRaw)) {
      return 'Enter a valid email address';
    }

    state = state.copyWith(status: ProfileEditStatus.saving, clearError: true);
    try {
      await _repo.updateProfile(
          name: name, email: emailRaw.isEmpty ? null : emailRaw);
      if (!ref.mounted) return null;
      state = state.copyWith(
        status: ProfileEditStatus.ready,
        name: name,
        email: emailRaw.isEmpty ? null : emailRaw,
        saved: true,
      );
      return null;
    } on ApiException catch (e) {
      // A save can outlive the screen (quick pop) — never touch state then.
      if (!ref.mounted) return e.message;
      state = state.copyWith(status: ProfileEditStatus.ready, error: e.message);
      return e.message;
    } catch (_) {
      const msg = 'Could not save your profile. Check your connection.';
      if (!ref.mounted) return msg;
      state = state.copyWith(status: ProfileEditStatus.ready, error: msg);
      return msg;
    }
  }
}

final profileEditControllerProvider =
    NotifierProvider<ProfileEditController, ProfileEditState>(
  ProfileEditController.new,
);
