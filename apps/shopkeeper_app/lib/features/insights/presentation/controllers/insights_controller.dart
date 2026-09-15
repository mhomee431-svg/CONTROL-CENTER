import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/token_store.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../data/insights_repository.dart';
import '../../domain/insights_models.dart';

/// Load states for the Reports / Insights screen.
enum InsightsStatus { loading, ready, noShop, accessDenied, error }

class InsightsState {
  const InsightsState({
    required this.status,
    this.bundle,
    this.rangeDays = kInsightsDefaultRange,
    this.message,
  });

  final InsightsStatus status;
  final InsightsBundle? bundle;

  /// Trailing window (days) the current [bundle] was computed for.
  final int rangeDays;
  final String? message;

  factory InsightsState.loading({int rangeDays = kInsightsDefaultRange}) =>
      InsightsState(status: InsightsStatus.loading, rangeDays: rangeDays);

  /// Shown when no shop is selected yet — the screen asks for shop setup
  /// instead of reporting on nothing.
  factory InsightsState.noShop({int rangeDays = kInsightsDefaultRange}) =>
      InsightsState(status: InsightsStatus.noShop, rangeDays: rangeDays);

  bool get isReady => status == InsightsStatus.ready && bundle != null;
}

final insightsControllerProvider =
    NotifierProvider<InsightsController, InsightsState>(InsightsController.new);

class InsightsController extends Notifier<InsightsState> {
  @override
  InsightsState build() => InsightsState.loading();

  InsightsRepository get _repo => ref.read(insightsRepositoryProvider);

  /// Loads the full analytics report for the selected shop. [days] switches
  /// the reporting window (defaults to the current / default range).
  Future<void> load({int? days}) async {
    final rangeDays = days ?? state.rangeDays;
    final shop = ref.read(selectedShopProvider);
    if (shop == null) {
      state = InsightsState.noShop(rangeDays: rangeDays);
      return;
    }
    state = InsightsState.loading(rangeDays: rangeDays);
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) throw const ApiException(message: 'Not signed in');
      final bundle = await _repo.fetchInsights(shop.id, token, days: rangeDays);
      state = InsightsState(
        status: InsightsStatus.ready,
        bundle: bundle,
        rangeDays: rangeDays,
      );
    } on ApiException catch (e) {
      // The backend refuses shops the user holds no `dashboard:read` grant on
      // — a distinct state, not a generic failure.
      state = InsightsState(
        status: e.isForbidden
            ? InsightsStatus.accessDenied
            : InsightsStatus.error,
        rangeDays: rangeDays,
        message: e.message,
      );
    } catch (_) {
      state = InsightsState(
        status: InsightsStatus.error,
        rangeDays: rangeDays,
        message: 'Could not load your reports.',
      );
    }
  }

  /// Switches the reporting window and reloads the report.
  Future<void> setRange(int days) => load(days: days);

  /// Clears cached report data (called on logout) so the previous account's
  /// customer metrics never survive into the next session.
  void reset() => state = InsightsState.loading();
}
