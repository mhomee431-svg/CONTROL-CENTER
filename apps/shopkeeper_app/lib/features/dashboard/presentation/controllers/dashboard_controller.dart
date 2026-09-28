import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/token_store.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../../inventory/data/inventory_repository.dart';
import '../../../inventory_import/data/import_repository.dart';
import '../../../notifications/presentation/controllers/notifications_controller.dart';
import '../../../shell/capabilities_controller.dart'
    show capabilitiesControllerProvider;
import '../../data/dashboard_repository.dart';
import '../../domain/dashboard_models.dart';

enum DashboardStatus { loading, ready, accessDenied, noShop, error }

class DashboardState {
  const DashboardState({
    required this.status,
    this.data,
    this.alerts = const DashboardAlerts(),
    this.message,
  });

  final DashboardStatus status;
  final DashboardData? data;

  /// "Needs attention" signals (req 21) — fail-soft, never blocks the load.
  final DashboardAlerts alerts;
  final String? message;

  factory DashboardState.loading() =>
      const DashboardState(status: DashboardStatus.loading);

  /// Shown immediately after login when the shopkeeper hasn't created their
  /// first shop yet — a welcoming home instead of a hard error.
  factory DashboardState.noShop() =>
      const DashboardState(status: DashboardStatus.noShop);
}

final dashboardControllerProvider =
    NotifierProvider<DashboardController, DashboardState>(
        DashboardController.new);

class DashboardController extends Notifier<DashboardState> {
  @override
  DashboardState build() => DashboardState.loading();

  DashboardRepository get _repo => ref.read(dashboardRepositoryProvider);

  Future<void> load() async {
    final shop = ref.read(selectedShopProvider);
    if (shop == null) {
      state = DashboardState.noShop();
      return;
    }
    state = DashboardState.loading();
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) throw const ApiException(message: 'Not signed in');
      final data = await _repo.fetchDashboard(shop.id, token);
      final alerts = await _loadAlerts(shop.id, token, data);
      // Publish the backend-driven flags to the ONE centralized layer so
      // every screen gates off the same source (no duplicated plan logic).
      ref
          .read(capabilitiesControllerProvider.notifier)
          .adopt(data.capabilities);
      state = DashboardState(
          status: DashboardStatus.ready, data: data, alerts: alerts);
    } on ApiException catch (e) {
      // Backend refuses unauthorized shops with 403 — surface a distinct
      // state instead of a generic failure.
      state = e.isForbidden
          ? DashboardState(
              status: DashboardStatus.accessDenied, message: e.message)
          : DashboardState(
              status: DashboardStatus.error, message: e.message);
    } catch (_) {
      state = const DashboardState(
          status: DashboardStatus.error,
          message: 'Could not load the dashboard.');
    }
  }

  /// Gathers the "needs attention" signals for the priority card (req 21):
  /// failed/partial import jobs, stale inventory, unread notifications.
  ///
  /// Each lookup is independent and fails soft — an error only hides its
  /// priority row; it never fails the dashboard load itself.
  Future<DashboardAlerts> _loadAlerts(
      int shopId, String token, DashboardData data) async {
    final failedImport = await _guard(() async {
      // One small page is enough for a "needs attention" signal: the newest
      // jobs are the ones the shopkeeper can still act on.
      final page = await ref
          .read(inventoryImportRepositoryProvider)
          .listJobs(shopId, token, limit: 10);
      for (final job in page.jobs) {
        // Newest first — the first FAILED job (or one stored with row
        // errors) is the one the shopkeeper should fix.
        if (job.status == 'FAILED' || (job.status == 'PARTIAL' && job.hasErrors)) {
          return job;
        }
      }
      return null;
    });
    // SINGLE SOURCE OF TRUTH (unread notifications): the count lives ONLY in
    // NotificationsController (which owns the optimistic mark-as-read
    // updates). The dashboard asks that controller for its count instead of
    // fetching the notifications page itself — a second copy here would
    // drift from the badge the moment the shopkeeper reads a notification.
    final unread = await _guard(() async {
      await ref.read(notificationsControllerProvider.notifier).load();
      return ref.read(notificationsControllerProvider).unreadCount;
    });
    final stale = await _guard(() async {
      // COUNTS ONLY (`view=summary`). This used to call
      // fetchInventoryOverview, which returns EVERY listing in the shop —
      // a full-catalogue download on the first screen after login, purely to
      // count how many rows are stale. The server already owns that count, so
      // the home screen now asks for the number and nothing else.
      final summary = await ref
          .read(inventoryRepositoryProvider)
          .fetchInventorySummary(shopId, token);
      return summary.stale;
    });

    final job = failedImport;
    return DashboardAlerts(
      failedImportName: job?.filename,
      failedImportRows: job?.errorRows ?? 0,
      staleCount: stale ?? 0,
      unreadNotifications: unread ?? 0,
    );
  }

  /// Runs a lookup and converts any failure into `null` (fail soft).
  Future<T?> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } catch (_) {
      return null;
    }
  }

  bool _refreshInFlight = false;

  /// Re-fetches the dashboard WITHOUT blanking the screen (silent refresh).
  ///
  /// Background resume/reconnect refreshes (see
  /// `features/shell/app_lifecycle_controller.dart`) use this instead of
  /// [load]: the shopkeeper keeps seeing the last numbers while fresh ones
  /// load, and a failure keeps the current view instead of throwing an error
  /// over working data. A re-entrant call while one refresh is running is
  /// dropped, never queued.
  Future<void> refresh() async {
    if (_refreshInFlight) return;
    final shop = ref.read(selectedShopProvider);
    if (shop == null) return;
    _refreshInFlight = true;
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      // Signed out mid-flight → keep the current view; logout resets state.
      if (token == null) return;
      final data = await _repo.fetchDashboard(shop.id, token);
      final alerts = await _loadAlerts(shop.id, token, data);
      ref.read(capabilitiesControllerProvider.notifier).adopt(data.capabilities);
      state = DashboardState(
          status: DashboardStatus.ready, data: data, alerts: alerts);
    } catch (_) {
      // Silent: a failed background refresh keeps the current state — the
      // next resume/reconnect/user pull-to-refresh tries again.
    } finally {
      _refreshInFlight = false;
    }
  }

  /// Clears ALL cached dashboard data (called on logout) so the previous
  /// account's operational numbers never survive into the next session.
  void reset() => state = DashboardState.loading();
}
