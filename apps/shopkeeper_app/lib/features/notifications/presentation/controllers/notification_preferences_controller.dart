import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../data/notification_preferences_store.dart';
import '../../domain/notification_models.dart';

enum NotificationPreferencesStatus { loading, ready }

/// State behind the notification-preferences screen.
class NotificationPreferencesState {
  const NotificationPreferencesState({
    this.status = NotificationPreferencesStatus.loading,
    this.preferences = const NotificationPreferences(),
    this.saved = const NotificationPreferences(),
    this.saving = false,
  });

  final NotificationPreferencesStatus status;

  /// What the switches currently show (may contain unsaved edits).
  final NotificationPreferences preferences;

  /// The last persisted snapshot — what "Discard" restores.
  final NotificationPreferences saved;

  /// True while a save is in flight.
  final bool saving;

  /// Drives the "You have unsaved changes" bar on the screen.
  bool get hasUnsavedChanges => preferences != saved;

  NotificationPreferencesState copyWith({
    NotificationPreferencesStatus? status,
    NotificationPreferences? preferences,
    NotificationPreferences? saved,
    bool? saving,
  }) =>
      NotificationPreferencesState(
        status: status ?? this.status,
        preferences: preferences ?? this.preferences,
        saved: saved ?? this.saved,
        saving: saving ?? this.saving,
      );
}

/// Delivery preferences for the signed-in shopkeeper.
///
/// There is no shopkeeper notification-settings endpoint yet, so this controller
/// persists to the device through `NotificationPreferencesStore` (see that file
/// for the rationale). Swapping the store for an API-backed implementation is
/// the ONLY change needed to move the same UI onto the server.
class NotificationPreferencesController
    extends Notifier<NotificationPreferencesState> {
  NotificationPreferencesStore get _store =>
      ref.read(notificationPreferencesStoreProvider);

  @override
  NotificationPreferencesState build() =>
      const NotificationPreferencesState();

  /// Per-user storage key: two accounts on one device never share preferences.
  String get _userKey =>
      'u${ref.read(authControllerProvider).user?.id ?? 'anonymous'}';

  /// Loads the saved preferences. Defaults are used when nothing is stored OR
  /// when storage refuses to read, so the screen can never be stuck Loading.
  Future<void> load() async {
    state = state.copyWith(status: NotificationPreferencesStatus.loading);
    NotificationPreferences loaded;
    try {
      loaded = await _store.read(_userKey) ?? const NotificationPreferences();
    } catch (_) {
      loaded = const NotificationPreferences();
    }
    state = NotificationPreferencesState(
      status: NotificationPreferencesStatus.ready,
      preferences: loaded,
      saved: loaded,
    );
  }

  /// A switch was flipped — replaces the working copy. Nothing is persisted
  /// until [save] runs, so a half-edited screen never leaks to storage.
  void update(NotificationPreferences next) =>
      state = state.copyWith(preferences: next);

  /// Throws away the working copy and restores the persisted values.
  void discardChanges() => state = state.copyWith(preferences: state.saved);

  /// Persists the working copy. `false` means the write failed — the screen
  /// keeps its unsaved-changes bar and surfaces the error.
  Future<bool> save() async {
    if (state.saving) return false;
    state = state.copyWith(saving: true);
    try {
      await _store.write(_userKey, state.preferences);
      state = state.copyWith(saved: state.preferences, saving: false);
      return true;
    } catch (_) {
      state = state.copyWith(saving: false);
      return false;
    }
  }

  /// Clears cached preferences and unsaved edits (called on logout) so nothing
  /// from the previous account survives into the next session.
  void reset() => state = const NotificationPreferencesState();
}

final notificationPreferencesProvider =
    NotifierProvider<NotificationPreferencesController,
        NotificationPreferencesState>(NotificationPreferencesController.new);