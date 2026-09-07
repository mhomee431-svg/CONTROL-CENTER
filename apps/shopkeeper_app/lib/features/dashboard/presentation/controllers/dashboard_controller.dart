import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/token_store.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../data/dashboard_repository.dart';
import '../../domain/dashboard_models.dart';

enum DashboardStatus { loading, ready, accessDenied, error }

class DashboardState {
  const DashboardState({required this.status, this.data, this.message});

  final DashboardStatus status;
  final DashboardData? data;
  final String? message;

  factory DashboardState.loading() =>
      const DashboardState(status: DashboardStatus.loading);
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
      state = const DashboardState(
          status: DashboardStatus.error, message: 'No shop selected');
      return;
    }
    state = DashboardState.loading();
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) throw const ApiException(message: 'Not signed in');
      final data = await _repo.fetchDashboard(shop.id, token);
      state = DashboardState(status: DashboardStatus.ready, data: data);
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
}
