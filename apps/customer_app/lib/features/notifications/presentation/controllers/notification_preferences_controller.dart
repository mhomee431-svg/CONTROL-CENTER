import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/notification_preferences.dart';
import '../../domain/notification_repository.dart';

/// State wrapper for the notification preferences editor.
class NotificationPreferencesState {
  final NotificationPreferences preferences;
  final bool isLoading;

  /// Non-null when the last save failed and was rolled back.
  final String? error;

  const NotificationPreferencesState({
    this.preferences = NotificationPreferences.defaults,
    this.isLoading = true,
    this.error,
  });

  NotificationPreferencesState copyWith({
    NotificationPreferences? preferences,
    bool? isLoading,
    String? error,
  }) {
    return NotificationPreferencesState(
      preferences: preferences ?? this.preferences,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

final notificationPreferencesControllerProvider =
    NotifierProvider<
      NotificationPreferencesController,
      NotificationPreferencesState
    >(NotificationPreferencesController.new);

/// Loads and updates per-type/per-channel notification delivery
/// preferences through the repository abstraction.
///
/// Local-first: with the mock repository everything persists on device;
/// once the backend ships, the same calls sync to the account. Failures
/// roll back to the previous value and surface [NotificationPreferencesState.error].
class NotificationPreferencesController
    extends Notifier<NotificationPreferencesState> {
  @override
  NotificationPreferencesState build() {
    Future.microtask(_load);
    return const NotificationPreferencesState();
  }

  Future<void> _load() async {
    try {
      final repository = ref.read(notificationsRepositoryProvider);
      final prefs = await repository.getPreferences();
      state = state.copyWith(preferences: prefs, isLoading: false);
    } catch (_) {
      // Fall back to defaults rather than blocking the settings UI.
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> reload() async {
    state = state.copyWith(isLoading: true);
    await _load();
  }

  /// Optimistically applies [change], then persists; rolls back + flags
  /// an error when the repository rejects it.
  Future<void> update(
    NotificationPreferences Function(NotificationPreferences) change,
  ) async {
    final previous = state.preferences;
    final optimistic = change(previous);
    state = state.copyWith(preferences: optimistic, error: null);
    try {
      final repository = ref.read(notificationsRepositoryProvider);
      await repository.updatePreferences(optimistic);
    } catch (_) {
      state = state.copyWith(
        preferences: previous,
        error: 'Could not save your notification preferences.',
      );
    }
  }

  // ── Channel toggles ────────────────────────────────────────────────
  Future<void> setPush(bool value) =>
      update((p) => p.copyWith(pushEnabled: value));
  Future<void> setEmail(bool value) =>
      update((p) => p.copyWith(emailEnabled: value));
  Future<void> setSms(bool value) =>
      update((p) => p.copyWith(smsEnabled: value));

  // ── Type toggles ───────────────────────────────────────────────────
  // Only the categories the backend can actually gate. The backend decision
  // table (`notification_service._TYPE_REGISTRY`) maps only these three
  // fields to customer-facing types:
  //   price_alerts       -> PRICE_DROP
  //   availability_alerts-> PRODUCT_AVAILABLE
  //   deal_alerts        -> OFFER
  Future<void> setPriceAlerts(bool value) =>
      update((p) => p.copyWith(priceAlerts: value));
  Future<void> setAvailabilityAlerts(bool value) =>
      update((p) => p.copyWith(availabilityAlerts: value));
  Future<void> setPromotional(bool value) =>
      update((p) => p.copyWith(promotional: value));
  Future<void> setDealAlerts(bool value) =>
      update((p) => p.copyWith(dealAlerts: value));

  /// Sets both offer-related fields together.
  ///
  /// "Offers and deals" is one customer-facing switch backed by two columns;
  /// binding them as a pair is what stops the two from disagreeing on screen.
  Future<void> setOffers(bool value) =>
      update((p) => p.copyWith(promotional: value, dealAlerts: value));
}
