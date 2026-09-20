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
    this.devices = const [],
    this.devicesLoading = false,
    this.message,
  });

  final PosStatus status;

  /// The shop's connector, or null when none has been registered yet.
  final PosIntegration? integration;
  final List<PosSyncJob> jobs;

  /// Vendor catalogue, populated when no connector exists (connect UI).
  final List<PosProviderInfo> providers;

  /// Terminals mapped to the connector (`GET .../devices`), loaded lazily by
  /// the Terminals sheet — never fetched just to render the status card.
  final List<PosDevice> devices;
  final bool devicesLoading;

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

  /// ── Terminals, schedule, settings, diagnostics ──────────────────────────
  ///
  /// Everything the connector API offers beyond load/connect/sync.

  /// Rebuilds state preserving everything that did NOT change, so a secondary
  /// action (devices, settings, retry) can never blank the loaded screen.
  PosState _patch({
    List<PosDevice>? devices,
    bool? devicesLoading,
    PosIntegration? integration,
    String? message,
  }) {
    final current = state;
    return PosState(
      status: PosStatus.ready,
      integration: integration ?? current.integration,
      jobs: current.jobs,
      providers: current.providers,
      devices: devices ?? current.devices,
      devicesLoading: devicesLoading ?? current.devicesLoading,
      message: message,
    );
  }

  /// Loads the terminals mapped to the connector (`GET .../devices`).
  ///
  /// Devices are a secondary view, so a failure reports itself without tearing
  /// down the connector card.
  Future<void> loadDevices() async {
    final integration = state.integration;
    if (integration == null) return;
    state = _patch(devicesLoading: true);
    try {
      final token = await _token();
      final devices = await _repo.listDevices(integration.id, token);
      state = _patch(devices: devices, devicesLoading: false);
    } on ApiException catch (e) {
      state = _patch(devicesLoading: false, message: friendlyPosError(e));
    } catch (_) {
      state = _patch(
        devicesLoading: false,
        message: 'Could not load the POS terminals.',
      );
    }
  }

  /// Maps a terminal to the connector, then reloads the list and the status
  /// card so the device count is always the server's number, never a guess.
  Future<bool> registerTerminal({
    required String deviceIdentifier,
    String? deviceName,
    String? deviceType,
  }) async {
    final integration = state.integration;
    if (integration == null) return false;
    try {
      final token = await _token();
      await _repo.registerDevice(
        integration.id,
        token,
        deviceIdentifier: deviceIdentifier,
        deviceName: deviceName,
        deviceType: deviceType,
      );
      final results = await Future.wait<dynamic>([
        _repo.listDevices(integration.id, token),
        _repo.status(integration.id, token),
      ]);
      state = _patch(
        devices: results[0] as List<PosDevice>,
        integration: results[1] as PosIntegration,
      );
      return true;
    } on ApiException catch (e) {
      state = _patch(
        message: friendlyPosError(
          e,
          forbidden: 'Only shop owners can manage POS terminals.',
        ),
      );
      return false;
    } catch (_) {
      state = _patch(message: 'Could not add the terminal. Please retry.');
      return false;
    }
  }

  /// Pauses/resumes background sync or changes its cadence
  /// (`PUT .../schedule`). Null fields are left untouched server-side.
  Future<bool> updateSchedule({bool? syncEnabled, int? intervalMinutes}) async {
    final integration = state.integration;
    if (integration == null) return false;
    try {
      final token = await _token();
      final fresh = await _repo.updateSchedule(
        integration.id,
        token,
        syncEnabled: syncEnabled,
        syncIntervalMinutes: intervalMinutes,
      );
      state = _patch(integration: fresh);
      return true;
    } on ApiException catch (e) {
      state = _patch(
        message: friendlyPosError(
          e,
          forbidden: 'Only shop owners can change the sync schedule.',
        ),
      );
      return false;
    } catch (_) {
      state = _patch(
        message: 'Could not save the sync schedule. Please retry.',
      );
      return false;
    }
  }

  /// Merges the vendor-neutral sync settings (`PUT .../config`).
  Future<bool> updateSyncSettings(PosSyncSettings settings) async {
    final integration = state.integration;
    if (integration == null) return false;
    try {
      final token = await _token();
      final fresh =
          await _repo.updateSyncConfig(integration.id, token, settings);
      state = _patch(integration: fresh);
      return true;
    } on ApiException catch (e) {
      state = _patch(
        message: friendlyPosError(
          e,
          forbidden: 'Only shop owners can change the sync settings.',
        ),
      );
      return false;
    } catch (_) {
      state = _patch(message: 'Could not save the sync settings. Please retry.');
      return false;
    }
  }

  /// One job WITH its diagnostics (`GET /shopkeeper/pos/jobs/{id}`).
  /// Returns null on failure — [PosState.message] then carries why.
  Future<PosJobDetail?> jobDetail(int jobId) async {
    try {
      final token = await _token();
      return await _repo.jobDetail(jobId, token);
    } on ApiException catch (e) {
      state = _patch(message: friendlyPosError(e));
      return null;
    } catch (_) {
      state = _patch(message: 'Could not load the job details.');
      return null;
    }
  }

  /// Re-runs a FAILED job and refreshes status + history so the retry shows up.
  /// Returns the retried job, or null when the backend refused (409).
  Future<PosSyncJob?> retryFailedJob(int jobId) async {
    final integration = state.integration;
    if (integration == null) return null;
    try {
      final token = await _token();
      final job = await _repo.retryJob(jobId, token);
      await _refreshActive(integration.id, token);
      return job;
    } on ApiException catch (e) {
      state = _patch(message: friendlyPosError(e));
      return null;
    } catch (_) {
      state = _patch(message: 'Could not retry the sync. Please retry.');
      return null;
    }
  }

  /// Refreshes ONLY the sync-job history, keeping the loaded connector in
  /// place. Used by the Sync History screen so a refresh never flashes the
  /// whole module back to a spinner.
  Future<void> refreshJobs() async {
    final integration = state.integration;
    if (integration == null) return;
    try {
      final token = await _token();
      final jobs = await _repo.listJobs(integration.id, token);
      state = PosState(
        status: PosStatus.ready,
        integration: integration,
        jobs: jobs,
        providers: state.providers,
      );
    } on ApiException catch (e) {
      state = PosState(
        status: PosStatus.error,
        message: friendlyPosError(e),
        integration: integration,
        jobs: state.jobs,
      );
    } catch (_) {
      state = PosState(
        status: PosStatus.error,
        message: 'Could not load the sync history.',
        integration: integration,
        jobs: state.jobs,
      );
    }
  }
}

// ── Polling cadence ─────────────────────────────────────────────────────────

/// How often the Sync Progress screen re-reads the server while a job is in
/// flight. Injectable so tests can advance the RUNNING → terminal transition
/// without waiting real seconds.
final posSyncPollIntervalProvider = Provider<Duration>(
  (_) => const Duration(seconds: 2),
);

/// Auto-poll safety cap: past this many refreshes the Progress screen stops its
/// timer and hands the refresh button back to the shopkeeper — a provider that
/// never reports completion must not spin forever.
const int kPosSyncMaxPolls = 30;

// ── Connection setup ────────────────────────────────────────────────────────

/// Lifecycle of the connection-setup flow.
enum PosSetupStatus { idle, loading, connecting, done, error }

class PosSetupState {
  const PosSetupState({
    required this.status,
    this.providers = const [],
    this.selectedProvider,
    this.integrationType = 'API',
    this.apiKey,
    this.apiSecret,
    this.apiBaseUrl,
    this.integration,
    this.message,
    this.credentialRefused = false,
    this.existing,
  });

  final PosSetupStatus status;

  /// The live vendor registry (`GET /shopkeeper/pos/providers`).
  final List<PosProviderInfo> providers;

  /// The vendor the shopkeeper picked (defaults to the registry's first).
  final String? selectedProvider;

  /// How the vendor talks to the backend: `API` | `FILE_UPLOAD` | `WEBHOOK`.
  final String integrationType;

  /// Optional vendor credentials. Blank fields are left untouched server-side,
  /// so a partial rotation is always a safe operation.
  final String? apiKey;
  final String? apiSecret;
  final String? apiBaseUrl;

  /// The connector once the link succeeded.
  final PosIntegration? integration;

  /// Error copy when [status] is [PosSetupStatus.error].
  final String? message;

  /// True when the VENDOR refused the link — not a network failure, so the
  /// setup stays open for correction instead of sending the shopkeeper away.
  final bool credentialRefused;

  /// An already-registered connector (reconnect / credential rotation), or null
  /// when this shop has none yet.
  final PosIntegration? existing;

  /// The provider code the flow will act on.
  String get effectiveProvider =>
      selectedProvider ?? (providers.isNotEmpty ? providers.first.code : '');

  PosSetupState copyWith({
    PosSetupStatus? status,
    List<PosProviderInfo>? providers,
    String? selectedProvider,
    String? integrationType,
    String? apiKey,
    String? apiSecret,
    String? apiBaseUrl,
    PosIntegration? integration,
    String? message,
    bool? credentialRefused,
    PosIntegration? existing,
  }) => PosSetupState(
    status: status ?? this.status,
    providers: providers ?? this.providers,
    selectedProvider: selectedProvider ?? this.selectedProvider,
    integrationType: integrationType ?? this.integrationType,
    apiKey: apiKey ?? this.apiKey,
    apiSecret: apiSecret ?? this.apiSecret,
    apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
    integration: integration ?? this.integration,
    message: message ?? this.message,
    credentialRefused: credentialRefused ?? this.credentialRefused,
    existing: existing ?? this.existing,
  );

  factory PosSetupState.initial() =>
      const PosSetupState(status: PosSetupStatus.idle);
}

final posSetupProvider = NotifierProvider<PosSetupController, PosSetupState>(
  PosSetupController.new,
);

/// Drives POS Connection Setup: pick a vendor from the registry, choose how it
/// talks to the backend, optionally rotate the vendor credentials, then
/// register + connect. The shop's existing connector (if any) is reconnected
/// instead of registering a duplicate.
class PosSetupController extends Notifier<PosSetupState> {
  @override
  PosSetupState build() => PosSetupState.initial();

  PosRepository get _repo => ref.read(posRepositoryProvider);

  int? get _shopId => ref.read(selectedShopProvider)?.id;

  Future<String> _token() async {
    final token = await ref.read(tokenStoreProvider).readAccessToken();
    if (token == null) throw const ApiException(message: 'Not signed in');
    return token;
  }

  /// Loads the registry and, when the shop already has a connector, opens the
  /// flow in "reconnect / rotate credentials" mode for it.
  Future<void> load() async {
    final existing = ref.read(posControllerProvider).integration;
    state = PosSetupState(status: PosSetupStatus.loading, existing: existing);
    try {
      final token = await _token();
      final providers = await _repo.listProviders(token);
      state = PosSetupState(status: PosSetupStatus.idle, providers: providers, existing: existing);
    } on ApiException catch (e) {
      state = PosSetupState(status: PosSetupStatus.error, message: friendlyPosError(e), existing: existing);
    } catch (_) {
      state = PosSetupState(
        status: PosSetupStatus.error,
        message: 'Could not load the POS providers.',
        existing: existing,
      );
    }
  }

  void selectProvider(String code) =>
      state = state.copyWith(selectedProvider: code);

  void selectIntegrationType(String type) =>
      state = state.copyWith(integrationType: type);

  void editCredentials({String? apiKey, String? apiSecret, String? apiBaseUrl}) =>
      state = state.copyWith(
        apiKey: apiKey,
        apiSecret: apiSecret,
        apiBaseUrl: apiBaseUrl,
      );

  /// Clears a one-off error once it has been surfaced (message must be
  /// explicitly reset, so this builds a fresh state rather than `copyWith`).
  void clearError() {
    if (state.status == PosSetupStatus.error) {
      state = PosSetupState(
        status: PosSetupStatus.idle,
        providers: state.providers,
        selectedProvider: state.selectedProvider,
        integrationType: state.integrationType,
        apiKey: state.apiKey,
        apiSecret: state.apiSecret,
        apiBaseUrl: state.apiBaseUrl,
        integration: state.integration,
        existing: state.existing,
      );
    }
  }

  /// Registers the connector (or reuses the existing one), applies the optional
  /// credentials, then validates the link. Returns true on success.
  Future<bool> submit() async {
    final shopId = _shopId;
    if (shopId == null) {
      state = state.copyWith(status: PosSetupStatus.error, message: 'No shop selected');
      return false;
    }
    final existing = state.existing;
    final provider = state.effectiveProvider;
    if (existing == null && provider.isEmpty) {
      state = state.copyWith(
        status: PosSetupStatus.error,
        message: 'Pick a POS provider to connect.',
      );
      return false;
    }
    state = _keepForm(status: PosSetupStatus.connecting);
    try {
      final token = await _token();
      final integration =
          existing ??
          await _repo.register(
            shopId,
            provider,
            token,
            integrationType: state.integrationType,
          );
      // Credentials are optional — only rotate when the shopkeeper typed any.
      final s = state;
      final hasCredentials =
          (s.apiKey?.trim().isNotEmpty ?? false) ||
          (s.apiSecret?.trim().isNotEmpty ?? false) ||
          (s.apiBaseUrl?.trim().isNotEmpty ?? false);
      final saved = hasCredentials
          ? await _saveCredentials(integration.id, token)
          : integration;
      final linked = existing != null
          ? await _repo.reconnect(integration.id, token)
          : await _repo.connect(integration.id, token);
      if (!linked) {
        state = state.copyWith(
          status: PosSetupStatus.error,
          integration: saved,
          credentialRefused: true,
          message: existing != null
              ? 'Reconnection failed — the vendor did not accept the link.'
              : 'Connection failed — check the credentials and retry',
        );
        return false;
      }
      final connected = await _repo.status(integration.id, token);
      state = PosSetupState(
        status: PosSetupStatus.done,
        providers: state.providers,
        selectedProvider: state.selectedProvider,
        integrationType: state.integrationType,
        integration: connected,
        existing: existing,
      );
      // The integration hub stays authoritative — refresh it in the background
      // so a pop back never shows a stale connector.
      await ref.read(posControllerProvider.notifier).load();
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(
        status: PosSetupStatus.error,
        message: friendlyPosError(
          e,
          forbidden: 'Only shop owners can connect a POS.',
        ),
      );
      return false;
    } catch (_) {
      state = state.copyWith(
        status: PosSetupStatus.error,
        message: 'Could not connect the POS. Please retry.',
      );
      return false;
    }
  }

  /// Applies the optional vendor credentials. Only the fields the shopkeeper
  /// typed are sent, so a rotation never blanks an existing secret.
  Future<PosIntegration> _saveCredentials(int integrationId, String token) =>
      _repo.updateCredentials(
        integrationId,
        token,
        apiKey: _clean(state.apiKey),
        apiSecret: _clean(state.apiSecret),
        apiBaseUrl: _clean(state.apiBaseUrl),
      );

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// Rebuilds the form state with a new [status] while clearing the one-off
  /// `message` — `copyWith` cannot reset a nullable field to null.
  PosSetupState _keepForm({required PosSetupStatus status}) => PosSetupState(
    status: status,
    providers: state.providers,
    selectedProvider: state.selectedProvider,
    integrationType: state.integrationType,
    apiKey: state.apiKey,
    apiSecret: state.apiSecret,
    apiBaseUrl: state.apiBaseUrl,
    integration: state.integration,
    existing: state.existing,
    credentialRefused: state.credentialRefused,
  );
}

// ── Sync flow (Sync → Progress → Result) ────────────────────────────────────

/// Lifecycle of one manual sync, end to end.
enum PosSyncPhase { idle, starting, running, done, error }

class PosSyncFlowState {
  const PosSyncFlowState({
    required this.phase,
    this.syncType = 'FULL',
    this.job,
    this.integration,
    this.message,
    this.polls = 0,
  });

  final PosSyncPhase phase;

  /// What the shopkeeper asked for: `FULL` | `INCREMENTAL`.
  final String syncType;

  /// The job this flow is watching (the queued one, then its freshest state).
  final PosSyncJob? job;

  /// The connector the job belongs to.
  final PosIntegration? integration;

  /// Error copy when [phase] is [PosSyncPhase.error].
  final String? message;

  /// How many times the server has been re-read (drives the poll cap).
  final int polls;

  /// True once the server reported the job finished (successfully or not).
  bool get isFinished => job != null && (job!.isDone || job!.isFailed);

  PosSyncFlowState copyWith({
    PosSyncPhase? phase,
    String? syncType,
    PosSyncJob? job,
    PosIntegration? integration,
    String? message,
    int? polls,
  }) => PosSyncFlowState(
    phase: phase ?? this.phase,
    syncType: syncType ?? this.syncType,
    job: job ?? this.job,
    integration: integration ?? this.integration,
    message: message ?? this.message,
    polls: polls ?? this.polls,
  );
}

final posSyncFlowProvider = NotifierProvider<PosSyncFlowController,
    PosSyncFlowState>(PosSyncFlowController.new);

/// Drives one manual sync: queue it (`POST .../sync`), then follow it on the
/// server (`GET .../status`) until the backend reports it finished. The screen
/// owns the timer; this controller owns the state transitions.
class PosSyncFlowController extends Notifier<PosSyncFlowState> {
  @override
  PosSyncFlowState build() => const PosSyncFlowState(phase: PosSyncPhase.idle);

  PosRepository get _repo => ref.read(posRepositoryProvider);

  Future<String> _token() async {
    final token = await ref.read(tokenStoreProvider).readAccessToken();
    if (token == null) throw const ApiException(message: 'Not signed in');
    return token;
  }

  /// Chooses the sync type before the job is queued.
  void selectType(String syncType) =>
      state = PosSyncFlowState(phase: PosSyncPhase.idle, syncType: syncType);

  /// Resets the flow so the next Sync screen opens clean.
  void reset() =>
      state = PosSyncFlowState(phase: PosSyncPhase.idle, syncType: state.syncType);

  /// Queues the sync for the shop's connector. Returns true when the job was
  /// accepted (the state then moves to [PosSyncPhase.running]).
  Future<bool> start() async {
    final integration = ref.read(posControllerProvider).integration;
    if (integration == null) {
      state = PosSyncFlowState(
        phase: PosSyncPhase.error,
        syncType: state.syncType,
        message: 'Connect a POS first — there is nothing to sync from.',
      );
      return false;
    }
    state = PosSyncFlowState(phase: PosSyncPhase.starting, syncType: state.syncType);
    try {
      final token = await _token();
      final job = await _repo.triggerSync(
        integration.id,
        token,
        syncType: state.syncType,
      );
      state = PosSyncFlowState(
        phase: PosSyncPhase.running,
        syncType: state.syncType,
        job: job,
        integration: integration,
      );
      // The backend may have processed the (small) job before we look again.
      await poll();
      return true;
    } on ApiException catch (e) {
      state = PosSyncFlowState(
        phase: PosSyncPhase.error,
        syncType: state.syncType,
        message: friendlyPosError(e),
      );
      return false;
    } catch (_) {
      state = PosSyncFlowState(
        phase: PosSyncPhase.error,
        syncType: state.syncType,
        message: 'Could not start the sync. Please retry.',
      );
      return false;
    }
  }

  /// Re-reads the connector's status and follows the tracked job. Safe to call
  /// repeatedly: it no-ops unless a job is in flight and the poll cap is open.
  Future<void> poll() async {
    final current = state;
    if (current.phase != PosSyncPhase.running || current.job == null) return;
    if (current.polls >= kPosSyncMaxPolls) return;
    final integration = current.integration;
    if (integration == null) return;
    try {
      final token = await _token();
      final fresh = await _repo.status(integration.id, token);
      final tracked = _trackedJob(fresh, current.job!);
      state = PosSyncFlowState(
        phase: tracked.isDone || tracked.isFailed
            ? PosSyncPhase.done
            : PosSyncPhase.running,
        syncType: current.syncType,
        job: tracked,
        integration: fresh,
        polls: current.polls + 1,
      );
    } on ApiException catch (e) {
      state = PosSyncFlowState(
        phase: PosSyncPhase.error,
        syncType: current.syncType,
        job: current.job,
        integration: integration,
        message: friendlyPosError(e),
        polls: current.polls,
      );
    } catch (_) {
      state = PosSyncFlowState(
        phase: PosSyncPhase.error,
        syncType: current.syncType,
        job: current.job,
        integration: integration,
        message: 'Could not read the sync progress. Please retry.',
        polls: current.polls,
      );
    }
  }

  /// Follows the queued job: the connector's `latestJob` wins when it IS the
  /// tracked job or a newer one (a scheduled sync may have jumped the queue).
  PosSyncJob _trackedJob(PosIntegration fresh, PosSyncJob tracked) {
    final latest = fresh.latestJob;
    if (latest == null) return tracked;
    return latest.id >= tracked.id ? latest : tracked;
  }
}

