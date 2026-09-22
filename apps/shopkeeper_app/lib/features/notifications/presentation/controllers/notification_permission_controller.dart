import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/permissions/data/permission_service.dart';
import '../../../../core/permissions/permission_models.dart';

/// Normalised device-notification state for the settings screen.
///
/// DELIBERATELY NOT BLOCKING (notification permission contract): nothing in
/// the app checks this status before rendering. A shopkeeper who never grants
/// notifications still gets every in-app alert — the grant only decides
/// whether the OS may also show banners and play sounds.
enum NotificationPermissionStatus {
  /// Reading the platform status.
  checking,

  /// Allowed — banners and sounds can appear.
  granted,

  /// Refused, but the OS will show the dialog again.
  denied,

  /// Permanently refused / locked by policy: only the system settings can
  /// change it.
  blocked,

  /// The platform cannot report a status (desktop/web build).
  unknown,
}

class NotificationPermissionState {
  const NotificationPermissionState({
    this.status = NotificationPermissionStatus.checking,
    this.requesting = false,
    this.message,
  });

  final NotificationPermissionStatus status;

  /// True while the OS dialog is up.
  final bool requesting;

  /// Result of the last [NotificationPermissionController.enable] call.
  final String? message;

  bool get isGranted => status == NotificationPermissionStatus.granted;
  bool get needsSettings => status == NotificationPermissionStatus.blocked;

  /// True while the status is still being read.
  bool get isChecking => status == NotificationPermissionStatus.checking;

  /// Status word for the settings row.
  String get statusLabel => switch (status) {
        NotificationPermissionStatus.granted => 'Allowed',
        NotificationPermissionStatus.denied => 'Not allowed',
        NotificationPermissionStatus.blocked => 'Blocked',
        NotificationPermissionStatus.checking => 'Checking…',
        NotificationPermissionStatus.unknown => 'Unknown',
      };

  NotificationPermissionState copyWith({
    NotificationPermissionStatus? status,
    bool? requesting,
    String? message,
    bool clearMessage = false,
  }) =>
      NotificationPermissionState(
        status: status ?? this.status,
        requesting: requesting ?? this.requesting,
        message: clearMessage ? null : (message ?? this.message),
      );
}

/// Drives *Settings → Notifications → device permission*.
///
/// WHY A SEPARATE CONTROLLER: the delivery preferences
/// (`NotificationPreferencesController`) answer "which alerts, through which
/// channel" and are stored per account. This one answers "may the OS show
/// anything at all", which only the platform knows and which can change while
/// the app is backgrounded — so it is re-read every time the screen opens.
class NotificationPermissionController
    extends Notifier<NotificationPermissionState> {
  PermissionService get _permissions => ref.read(permissionServiceProvider);

  @override
  NotificationPermissionState build() => const NotificationPermissionState();

  /// Reads the current status — never prompts the shopkeeper.
  Future<void> refresh() async {
    final snapshot = await _permissions.status(PermissionKind.notifications);
    state = NotificationPermissionState(status: _statusOf(snapshot.outcome));
  }

  /// "Enable Notifications": asks the platform and reports the outcome.
  /// Returns true when notifications are allowed afterwards.
  Future<bool> enable() async {
    if (state.requesting) return state.isGranted;
    state = state.copyWith(requesting: true, clearMessage: true);
    final snapshot = await _permissions.request(PermissionKind.notifications);
    final status = _statusOf(snapshot.outcome);
    state = NotificationPermissionState(
      status: status,
      requesting: false,
      message: switch (status) {
        NotificationPermissionStatus.granted =>
          'Notifications are allowed on this device.',
        NotificationPermissionStatus.denied =>
          'Notifications are still switched off. You can turn them on any '
              'time from here.',
        NotificationPermissionStatus.blocked =>
          'Notifications are blocked for this app. Turn them on in your '
              'phone settings.',
        NotificationPermissionStatus.unknown => null,
        NotificationPermissionStatus.checking => null,
      },
    );
    return status == NotificationPermissionStatus.granted;
  }

  /// Opens this app's system-settings page (the only route out of a permanent
  /// denial). Returns false when the platform refused.
  Future<bool> openSystemSettings() => _permissions.openSystemSettings();

  /// Clears the last attempt's message (called once the snackbar was shown).
  void clearMessage() {
    if (state.message != null) state = state.copyWith(clearMessage: true);
  }

  NotificationPermissionStatus _statusOf(PermissionOutcome outcome) =>
      switch (outcome) {
        PermissionOutcome.granted ||
        PermissionOutcome.limited =>
          NotificationPermissionStatus.granted,
        PermissionOutcome.denied => NotificationPermissionStatus.denied,
        PermissionOutcome.permanentlyDenied ||
        PermissionOutcome.restricted =>
          NotificationPermissionStatus.blocked,
        PermissionOutcome.unknown => NotificationPermissionStatus.unknown,
      };
}

final notificationPermissionProvider =
    NotifierProvider<NotificationPermissionController,
        NotificationPermissionState>(NotificationPermissionController.new);
