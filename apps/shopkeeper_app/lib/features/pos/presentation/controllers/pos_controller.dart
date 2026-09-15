import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/token_store.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../data/pos_repository.dart';
import '../../domain/pos_models.dart';

/// Lifecycle of the POS screen.
enum PosStatus { loading, ready, error, noShop }

class PosState {
  const PosState({
    required this.status,
    this.integration,
    this.jobs = const [],
    this.providers = const [],
    this.message,
  });

  final PosStatus status;

  /// The shop's connector, or null when none has been registered yet.
  final PosIntegration? integration;
  final List<PosSyncJob> jobs;

  /// Vendor catalogue, populated when no connector exists (connect UI).
  final List<PosProviderInfo> providers;

  /// Error copy when [status] is [PosStatus.error].
  final String? message;

  bool get needsOnboarding => integration == null;
}

final posControllerProvider =
    NotifierProvider<PosController, PosState>(PosController.new);

/// Drives the POS screen: discovers the shop's connector, renders its live
/// status and sync history, and forwards connect / disconnect / sync actions.
/// No business logic in widgets; every action reloads the authoritative
/// server state instead of mutating local guesses.
class PosController extends Notifier<PosState> {
  @override
  PosState build() => const PosState(status: PosStatus.loading);

  PosRepository get _repo => ref.read(posRepositoryProvider);

  int? get _shopId => ref.read(selectedShopProvider)?.id;

  /// Reads the access token or throws when the session is gone.
  Future<String> _token() async {
    final token = await ref.read(tokenStoreProvider).readAccessToken();
    if (token == null) throw const ApiException(message: 'Not signed in');
    return token;
  }

  /// Loads the shop's connector. With one registered, the aggregated
  /// `.../status` payload plus the job history populate the screen. Without
  /// one, the provider catalogue is fetched for the connect UI.
  Future<void> load() async {
    final shopId = _shopId;
    if (shopId == null) {
      state = const PosState(status: PosStatus.noShop);
      return;
    }
    state = const PosState(status: PosStatus.loading);
    try {
      final token = await _token();
      final integrations = await _repo.listIntegrations(shopId, token);
      if (integrations.isEmpty) {
        final providers = await _repo.listProviders(token);
        state = PosState(status: PosStatus.ready, providers: providers);
        return;
      }
      final integration = integrations.first;
      final results = await Future.wait([
        _repo.status(integration.id, token),
        _repo.listJobs(integration.id, token),
      ]);
      state = PosState(
        status: PosStatus.ready,
        integration: results[0] as PosIntegration,
        jobs: results[1] as List<PosSyncJob>,
      );
    } on ApiException catch (e) {
      state = PosState(status: PosStatus.error, message: friendlyPosError(e));
    } catch (_) {
      state = const PosState(
        status: PosStatus.error,
        message: 'Could not load POS integration.',
      );
    }
  }

  /// Registers the chosen provider, then validates credentials. Returns true
  /// when the connector ends up ACTIVE. A credential refusal keeps the error
  /// integration so the shopkeeper can retry the connect.
  Future<bool> connect(String providerCode) async {
    final shopId = _shopId;
    if (shopId == null) {
      state = const PosState(
        status: PosStatus.error,
        message: 'No shop selected',
      );
      return false;
    }
    try {
      final token = await _token();
      final registered = await _repo.register(shopId, providerCode, token);
      final connected = await _repo.connect(registered.id, token);
      await load();
      return connected;
    } on ApiException catch (e) {
      state = PosState(
        status: PosStatus.error,
        message:
            friendlyPosError(e, forbidden: 'Only shop owners can connect a POS.'),
      );
      return false;
    } catch (_) {
      state = const PosState(
        status: PosStatus.error,
        message: 'Could not connect the POS. Please retry.',
      );
      return false;
    }
  }

  /// Explicitly disconnects and reloads (stops scheduled syncs server-side).
  Future<void> disconnect() async {
    final integration = state.integration;
    if (integration == null) return;
    try {
      final token = await _token();
      await _repo.disconnect(integration.id, token);
    } on ApiException catch (e) {
      state = PosState(status: PosStatus.error, message: friendlyPosError(e));
      return;
    } catch (_) {
      state = const PosState(
        status: PosStatus.error,
        message: 'Could not disconnect the POS. Please retry.',
      );
      return;
    }
    await load();
  }

  /// Queues a manual sync job and immediately refreshes status + history so
  /// the queued/running job shows up. Returns the queued job, or null on
  /// failure (state carries the error copy).
  Future<PosSyncJob?> syncNow() async {
    final integration = state.integration;
    if (integration == null) return null;
    try {
      final token = await _token();
      final job = await _repo.triggerSync(integration.id, token);
      // The job is queued server-side; refresh to surface it in history.
      await _refreshActive(integration.id, token);
      return job;
    } on ApiException catch (e) {
      state = PosState(status: PosStatus.error, message: friendlyPosError(e));
      return null;
    } catch (_) {
      state = const PosState(
        status: PosStatus.error,
        message: 'Could not start the sync. Please retry.',
      );
      return null;
    }
  }

  Future<void> _refreshActive(int integrationId, String token) async {
    final results = await Future.wait([
      _repo.status(integrationId, token),
      _repo.listJobs(integrationId, token),
    ]);
    state = PosState(
      status: PosStatus.ready,
      integration: results[0] as PosIntegration,
      jobs: results[1] as List<PosSyncJob>,
    );
  }
}
