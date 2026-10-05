import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../permission_models.dart';

/// The app's ONE door to runtime permissions.
///
/// SCOPE: camera (barcode scanning). LOCATION deliberately stays out of this
/// service: `geolocator` already owns the location grant, and two owners for
/// one permission is how an app ends up asking twice or disagreeing with
/// itself. NOTIFICATIONS are handled by the push-notification stack.
///
/// Everything is funnelled through [PermissionOutcome], so a widget never sees
/// a `permission_handler` type and a widget test can script any outcome.
///
/// Mirrors the shopkeeper app's `PermissionService` (same names, same guarded
/// platform calls) so behaviour is identical across both apps.
abstract class PermissionService {
  /// Reads the current status WITHOUT prompting the customer.
  Future<PermissionSnapshot> status(PermissionKind kind);

  /// Asks the platform. Resolves to the resulting status — a granted
  /// permission resolves to [PermissionOutcome.granted] without a dialog.
  Future<PermissionSnapshot> request(PermissionKind kind);

  /// Opens this app's page in the system settings, the only route back from a
  /// permanently denied permission. `false` when the platform refused.
  Future<bool> openSystemSettings();
}

/// Production implementation. Every platform call is guarded: a missing plugin
/// implementation (desktop/web) must never crash the search screen — it
/// resolves to [PermissionOutcome.unknown] and the caller falls back to manual
/// barcode entry.
class PlatformPermissionService implements PermissionService {
  const PlatformPermissionService();

  @override
  Future<PermissionSnapshot> status(PermissionKind kind) async {
    try {
      return PermissionSnapshot(
        kind: kind,
        outcome: _outcome(await _handler(kind).status),
      );
    } catch (_) {
      return PermissionSnapshot(kind: kind, outcome: PermissionOutcome.unknown);
    }
  }

  @override
  Future<PermissionSnapshot> request(PermissionKind kind) async {
    try {
      return PermissionSnapshot(
        kind: kind,
        outcome: _outcome(await _handler(kind).request()),
      );
    } catch (_) {
      return PermissionSnapshot(kind: kind, outcome: PermissionOutcome.unknown);
    }
  }

  @override
  Future<bool> openSystemSettings() async {
    try {
      return await openAppSettings();
    } catch (_) {
      return false;
    }
  }

  Permission _handler(PermissionKind kind) => switch (kind) {
    PermissionKind.camera => Permission.camera,
  };

  PermissionOutcome _outcome(PermissionStatus status) {
    if (status.isGranted) return PermissionOutcome.granted;
    if (status.isLimited || status.isProvisional) {
      return PermissionOutcome.limited;
    }
    if (status.isPermanentlyDenied) return PermissionOutcome.permanentlyDenied;
    if (status.isRestricted) return PermissionOutcome.restricted;
    if (status.isDenied) return PermissionOutcome.denied;
    return PermissionOutcome.unknown;
  }
}

/// Scriptable fake for tests: no platform channels, deterministic outcomes.
///
/// A test can mutate the scripted outcomes between steps (e.g. "the customer
/// granted the permission while the app was in the background") without
/// touching another test's service.
class InMemoryPermissionService implements PermissionService {
  InMemoryPermissionService({
    Map<PermissionKind, PermissionOutcome>? statuses,
    Map<PermissionKind, PermissionOutcome>? requestOutcomes,
  }) : _statuses = {for (final e in (statuses ?? {}).entries) e.key: e.value},
       _requestOutcomes = {
         for (final e in (requestOutcomes ?? {}).entries) e.key: e.value,
       };

  final Map<PermissionKind, PermissionOutcome> _statuses;
  final Map<PermissionKind, PermissionOutcome> _requestOutcomes;

  /// Every [request] call, oldest first — lets a test prove the app asked
  /// exactly once, or re-asked after a denial.
  final List<PermissionKind> requests = [];

  /// Every [openSystemSettings] call.
  int openSettingsCalls = 0;

  /// What [openSystemSettings] resolves to.
  bool settingsOpenResult = true;

  /// Status a `status()` call resolves to when nothing was scripted.
  PermissionOutcome fallbackOutcome = PermissionOutcome.denied;

  /// Result of the NEXT `request()` call for [kind] (default [fallbackOutcome]).
  void scriptRequest(PermissionKind kind, PermissionOutcome outcome) =>
      _requestOutcomes[kind] = outcome;

  /// Current status reported for [kind].
  void setStatus(PermissionKind kind, PermissionOutcome outcome) =>
      _statuses[kind] = outcome;

  PermissionOutcome statusOf(PermissionKind kind) =>
      _statuses[kind] ?? fallbackOutcome;

  int requestsFor(PermissionKind kind) =>
      requests.where((k) => k == kind).length;

  @override
  Future<PermissionSnapshot> status(PermissionKind kind) async =>
      PermissionSnapshot(kind: kind, outcome: statusOf(kind));

  @override
  Future<PermissionSnapshot> request(PermissionKind kind) async {
    requests.add(kind);
    final outcome = _requestOutcomes[kind] ?? fallbackOutcome;
    // A real request also settles the status, so the next status() must agree
    // with what the customer just answered.
    _statuses[kind] = outcome;
    return PermissionSnapshot(kind: kind, outcome: outcome);
  }

  @override
  Future<bool> openSystemSettings() async {
    openSettingsCalls++;
    return settingsOpenResult;
  }
}

/// Default binding — override in tests with [InMemoryPermissionService].
final permissionServiceProvider = Provider<PermissionService>(
  (ref) => const PlatformPermissionService(),
);
