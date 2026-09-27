import '../../../core/network/api_client.dart';

/// One pluggable POS vendor from `GET /shopkeeper/pos/providers`.
class PosProviderInfo {
  const PosProviderInfo({
    required this.code,
    required this.displayName,
    required this.supportsIncremental,
  });

  /// Backend provider code, e.g. `MOCK`.
  final String code;
  final String displayName;
  final bool supportsIncremental;

  factory PosProviderInfo.fromJson(Map<String, dynamic> json) =>
      PosProviderInfo(
        code: json['code'] as String? ?? '',
        displayName: json['display_name'] as String? ?? json['code'] as String? ?? '',
        supportsIncremental: json['supports_incremental'] as bool? ?? false,
      );

  static List<PosProviderInfo> listFrom(dynamic raw) => raw is List
      ? raw
          .whereType<Map<String, dynamic>>()
          .map(PosProviderInfo.fromJson)
          .toList(growable: false)
      : const <PosProviderInfo>[];
}

/// One sync job from `GET .../integrations/{id}/jobs`.
class PosSyncJob {
  const PosSyncJob({
    required this.id,
    required this.syncType,
    required this.status,
    required this.trigger,
    required this.itemsProcessed,
    required this.itemsSucceeded,
    required this.itemsFailed,
    this.errorSummary,
    this.startedAt,
    this.completedAt,
  });

  final int id;
  final String syncType; // FULL | INCREMENTAL
  final String status; // QUEUED | RUNNING | COMPLETED | FAILED | …
  final String trigger; // MANUAL | SCHEDULED | WEBHOOK
  final int itemsProcessed;
  final int itemsSucceeded;
  final int itemsFailed;
  final String? errorSummary;
  final DateTime? startedAt;
  final DateTime? completedAt;

  bool get isQueued => status == 'QUEUED';
  bool get isRunning => status == 'RUNNING';
  bool get isDone => status == 'COMPLETED' || status == 'COMPLETED_WITH_ERRORS';
  bool get isFailed => status == 'FAILED';

  factory PosSyncJob.fromJson(Map<String, dynamic> json) => PosSyncJob(
        id: (json['id'] as num?)?.toInt() ?? 0,
        syncType: json['sync_type'] as String? ?? 'FULL',
        status: json['status'] as String? ?? 'QUEUED',
        trigger: json['trigger'] as String? ?? 'MANUAL',
        itemsProcessed: (json['items_processed'] as num?)?.toInt() ?? 0,
        itemsSucceeded: (json['items_succeeded'] as num?)?.toInt() ?? 0,
        itemsFailed: (json['items_failed'] as num?)?.toInt() ?? 0,
        errorSummary: json['error_summary'] as String?,
        startedAt: PosIntegration.parseDate(json['started_at']),
        completedAt: PosIntegration.parseDate(json['completed_at']),
      );

  static List<PosSyncJob> listFrom(dynamic raw) => raw is List
      ? raw
          .whereType<Map<String, dynamic>>()
          .map(PosSyncJob.fromJson)
          .toList(growable: false)
      : const <PosSyncJob>[];
}

/// One POS integration for the shop, as returned by
/// `GET /shopkeeper/pos/integrations?shop_id=` and `GET .../status`.
class PosIntegration {
  const PosIntegration({
    required this.id,
    required this.shopId,
    required this.providerCode,
    required this.providerName,
    required this.status,
    required this.syncEnabled,
    required this.syncIntervalMinutes,
    required this.mappedProducts,
    required this.deviceCount,
    this.lastSyncAt,
    this.lastSyncStatus,
    this.consecutiveFailures = 0,
    this.latestJob,
  });

  final int id;
  final int shopId;
  final String providerCode;
  final String providerName;

  /// ACTIVE | INACTIVE | PENDING | ERROR | DISCONNECTED.
  final String status;
  final bool syncEnabled;
  final int? syncIntervalMinutes;
  final int mappedProducts;
  final int deviceCount;
  final DateTime? lastSyncAt;
  final String? lastSyncStatus;
  final int consecutiveFailures;

  /// Newest sync job, when the payload carried one (`.../status`).
  final PosSyncJob? latestJob;

  bool get isConnected => status == 'ACTIVE';
  bool get isDisconnected => status == 'DISCONNECTED' || status == 'INACTIVE';
  bool get hasError => status == 'ERROR';

  /// True while a sync job is queued or running for this connector — the
  /// status card renders a distinct "Syncing" state instead of "Connected".
  bool get isSyncing {
    final latest = latestJob;
    if (latest != null && (latest.isQueued || latest.isRunning)) return true;
    // The aggregated status payload may omit latest_job; a running row in the
    // fetched history is equally authoritative.
    return lastSyncStatus == 'QUEUED' || lastSyncStatus == 'RUNNING';
  }

  factory PosIntegration.fromJson(Map<String, dynamic> json) => PosIntegration(
        id: (json['id'] as num?)?.toInt() ?? 0,
        shopId: (json['shop_id'] as num?)?.toInt() ?? 0,
        providerCode: json['provider_code'] as String? ?? '',
        providerName: json['provider_name'] as String? ?? json['provider_code'] as String? ?? '',
        status: json['status'] as String? ?? 'PENDING',
        syncEnabled: json['sync_enabled'] as bool? ?? false,
        syncIntervalMinutes: (json['sync_interval_minutes'] as num?)?.toInt(),
        mappedProducts: (json['mapped_products'] as num?)?.toInt() ?? 0,
        deviceCount: (json['devices'] as num?)?.toInt() ?? 0,
        lastSyncAt: parseDate(json['last_sync_at']),
        lastSyncStatus: json['last_sync_status'] as String?,
        consecutiveFailures: (json['consecutive_failures'] as num?)?.toInt() ?? 0,
        latestJob: json['latest_job'] is Map<String, dynamic>
            ? PosSyncJob.fromJson(json['latest_job'] as Map<String, dynamic>)
            : null,
      );

  static List<PosIntegration> listFromList(dynamic raw) => raw is List
      ? raw
          .whereType<Map<String, dynamic>>()
          .map(PosIntegration.fromJson)
          .toList(growable: false)
      : const <PosIntegration>[];

  static DateTime? parseDate(Object? raw) {
    if (raw is DateTime) return raw;
    if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw)?.toLocal();
    return null;
  }
}

/// One physically mapped POS terminal (`GET/POST .../devices`).
class PosDevice {
  const PosDevice({
    required this.id,
    required this.deviceIdentifier,
    required this.isActive,
    this.deviceName,
    this.deviceType,
    this.lastConnectedAt,
  });

  final int id;

  /// The vendor's immutable terminal id — the map key, so a re-registration
  /// refreshes the row instead of duplicating it.
  final String deviceIdentifier;
  final bool isActive;

  /// Optional friendly name; empty falls back to the identifier.
  final String? deviceName;

  /// `POS_TERMINAL | SCANNER | TABLET` (free-form on the backend).
  final String? deviceType;
  final DateTime? lastConnectedAt;

  String get displayName {
    final name = deviceName?.trim() ?? '';
    return name.isNotEmpty ? name : deviceIdentifier;
  }

  bool get isTerminal => deviceType == 'POS_TERMINAL';

  factory PosDevice.fromJson(Map<String, dynamic> json) => PosDevice(
        id: (json['id'] as num?)?.toInt() ?? 0,
        deviceIdentifier: json['device_identifier'] as String? ?? '',
        isActive: json['is_active'] as bool? ?? true,
        deviceName: json['device_name'] as String?,
        deviceType: json['device_type'] as String?,
        lastConnectedAt: PosIntegration.parseDate(json['last_connected_at']),
      );

  static List<PosDevice> listFrom(dynamic raw) => raw is List
      ? raw
          .whereType<Map<String, dynamic>>()
          .map(PosDevice.fromJson)
          .toList(growable: false)
      : const <PosDevice>[];
}

/// One log line from a job detail payload (`GET /shopkeeper/pos/jobs/{id}`).
class PosJobLog {
  const PosJobLog({
    required this.level,
    required this.message,
    this.itemReference,
    this.errorCode,
    this.loggedAt,
  });

  /// `INFO | WARNING | ERROR`.
  final String level;
  final String message;
  final String? itemReference;
  final String? errorCode;
  final DateTime? loggedAt;

  bool get isError => level.toUpperCase() == 'ERROR';
  bool get isWarning => level.toUpperCase() == 'WARNING';

  factory PosJobLog.fromJson(Map<String, dynamic> json) => PosJobLog(
        level: json['log_level'] as String? ?? 'INFO',
        message: json['message'] as String? ?? '',
        itemReference: json['item_reference'] as String?,
        errorCode: json['error_code'] as String?,
        loggedAt: PosIntegration.parseDate(json['logged_at']),
      );

  static List<PosJobLog> listFrom(dynamic raw) => raw is List
      ? raw
          .whereType<Map<String, dynamic>>()
          .map(PosJobLog.fromJson)
          .toList(growable: false)
      : const <PosJobLog>[];
}

/// Shared technical-exception → shopkeeper-copy mapper for POS failures.
String friendlyPosError(ApiException e, {String? forbidden}) {
  if (e.isUnauthorized || e.statusCode == 401) {
    return 'Your session has expired. Please sign in again.';
  }
  if (e.isForbidden || e.statusCode == 403) {
    // A PLAN refusal (403 + ENTITLEMENT_DENIED / SUBSCRIPTION_EXPIRED /
    // PLAN_LIMIT_REACHED) carries the server's own actionable copy —
    // "Your current plan does not include 'pos_support'. Upgrade to unlock
    // this feature." — which beats any generic permission wording: the fix is
    // an upgrade, not a different shop or a retry.
    if (e.isEntitlementDenied && e.message.trim().isNotEmpty) {
      return e.message;
    }
    return forbidden ?? 'You do not have permission to manage POS for this shop.';
  }
  if (e.statusCode == null) {
    return 'No internet connection. Check your network and retry.';
  }
  return e.message;
}

/// One mapping conflict a sync recorded: either the platform kept its value
/// (the POS value was logged, not applied) or the POS overwrote it traceably.
class PosJobConflict {
  const PosJobConflict({
    required this.posProductCode,
    required this.field,
    required this.detail,
    this.platformValue,
    this.posValue,
  });

  final String posProductCode;

  /// Which synchronized field disagreed (`price`, `inventory`, …).
  final String field;

  /// The backend's own sentence about the conflict, when present.
  final String detail;
  final String? platformValue;
  final String? posValue;

  factory PosJobConflict.fromJson(Map<String, dynamic> json) {
    String pick(List<String> keys) {
      for (final key in keys) {
        final value = json[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
      return '';
    }

    final platform = pick(const ['platform_value', 'platform']);
    final pos = pick(const ['pos_value', 'pos']);
    return PosJobConflict(
      posProductCode: json['pos_product_code'] as String? ?? '',
      field: pick(const ['field', 'field_name', 'attribute']),
      detail: pick(const ['message', 'reason', 'detail', 'description']),
      platformValue: platform.isEmpty ? null : platform,
      posValue: pos.isEmpty ? null : pos,
    );
  }

  static List<PosJobConflict> listFrom(dynamic raw) => raw is List
      ? raw
          .whereType<Map<String, dynamic>>()
          .map(PosJobConflict.fromJson)
          .toList(growable: false)
      : const <PosJobConflict>[];
}

/// A sync job WITH its diagnostics: `GET /shopkeeper/pos/jobs/{id}` returns the
/// job payload plus every log line and every recorded mapping conflict.
class PosJobDetail {
  const PosJobDetail({
    required this.job,
    this.logs = const [],
    this.conflicts = const [],
  });

  final PosSyncJob job;
  final List<PosJobLog> logs;
  final List<PosJobConflict> conflicts;

  bool get hasDiagnostics => logs.isNotEmpty || conflicts.isNotEmpty;

  factory PosJobDetail.fromJson(Map<String, dynamic> json) => PosJobDetail(
        job: PosSyncJob.fromJson(json),
        logs: PosJobLog.listFrom(json['logs']),
        conflicts: PosJobConflict.listFrom(json['conflicts']),
      );
}

/// The connector's vendor-neutral sync configuration (`config_json`).
///
/// The backend deep-merges whatever map this app sends, so only the knobs a
/// shopkeeper can reason about are offered here — never the whole bag.
class PosSyncSettings {
  const PosSyncSettings({this.batchSize, this.fieldAuthorities = const {}});

  /// Records applied per sync pass (backend default 500).
  final int? batchSize;

  /// Per-field authority override: `PLATFORM` (platform value kept, the POS
  /// value recorded as a conflict) or `POS` (the till wins, written traceably).
  ///
  /// Fields not listed keep the backend's own default and are never touched.
  final Map<String, String> fieldAuthorities;

  String authorityFor(String field) {
    final value = fieldAuthorities[field];
    if (value == null || value.trim().isEmpty) return 'PLATFORM';
    return value.trim().toUpperCase();
  }

  Map<String, dynamic> toRequest() => {
        if (batchSize != null) 'batch_size': batchSize,
        if (fieldAuthorities.isNotEmpty) 'field_authorities': fieldAuthorities,
      };
}
