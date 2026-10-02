import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/permissions/data/permission_service.dart';
import '../../../../core/permissions/permission_models.dart';
import '../../../../core/view/view_model.dart';
import '../../domain/barcode_validation.dart';

/// Status of camera permission for barcode scanning.
enum BarcodeCameraPermissionStatus {
  /// Checking permission or waiting for user decision.
  asking,

  /// Allowed — live camera preview can be displayed.
  ready,

  /// Denied once — can ask again.
  denied,

  /// Permanently denied or restricted by OS/policy — must open system settings.
  blocked,

  /// Error occurred during permission check or request.
  error;

  bool get isReady => this == ready;
  bool get isBlocked => this == blocked;
  bool get isDenied => this == denied;
  bool get isError => this == error;
  bool get isAsking => this == asking;
}

/// Structured record of an invalid barcode capture.
@immutable
class InvalidBarcode {
  const InvalidBarcode({required this.code, required this.reason});

  final String code;
  final BarcodeInvalidReason reason;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InvalidBarcode && code == other.code && reason == other.reason;

  @override
  int get hashCode => Object.hash(code, reason);

  @override
  String toString() => 'InvalidBarcode($code, $reason)';
}

/// State for barcode scanner screen and camera permission flow.
@immutable
class BarcodeScannerState {
  const BarcodeScannerState({
    this.permissionStatus = BarcodeCameraPermissionStatus.asking,
    this.isBusy = true,
    this.scannedBarcode,
    this.invalidBarcode,
    this.errorMessage,
  });

  /// Current permission lifecycle state.
  final BarcodeCameraPermissionStatus permissionStatus;

  /// True when an asynchronous permission check/request is active.
  final bool isBusy;

  /// The valid detected barcode whose results are shown.
  final String? scannedBarcode;

  /// A detected barcode that failed validation.
  final InvalidBarcode? invalidBarcode;

  /// Error message when [permissionStatus] is error or camera error occurs.
  final String? errorMessage;

  bool get isReady => permissionStatus == BarcodeCameraPermissionStatus.ready;
  bool get isBlocked =>
      permissionStatus == BarcodeCameraPermissionStatus.blocked;
  bool get isDenied => permissionStatus == BarcodeCameraPermissionStatus.denied;
  bool get isError => permissionStatus == BarcodeCameraPermissionStatus.error;
  bool get isAsking => permissionStatus == BarcodeCameraPermissionStatus.asking;

  bool get hasScannedBarcode => scannedBarcode != null;
  bool get hasInvalidBarcode => invalidBarcode != null;

  BarcodeScannerState copyWith({
    BarcodeCameraPermissionStatus? permissionStatus,
    bool? isBusy,
    String? scannedBarcode,
    InvalidBarcode? invalidBarcode,
    String? errorMessage,
    bool clearScannedBarcode = false,
    bool clearInvalidBarcode = false,
    bool clearError = false,
  }) {
    return BarcodeScannerState(
      permissionStatus: permissionStatus ?? this.permissionStatus,
      isBusy: isBusy ?? this.isBusy,
      scannedBarcode: clearScannedBarcode
          ? null
          : (scannedBarcode ?? this.scannedBarcode),
      invalidBarcode: clearInvalidBarcode
          ? null
          : (invalidBarcode ?? this.invalidBarcode),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BarcodeScannerState &&
          permissionStatus == other.permissionStatus &&
          isBusy == other.isBusy &&
          scannedBarcode == other.scannedBarcode &&
          invalidBarcode == other.invalidBarcode &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode => Object.hash(
    permissionStatus,
    isBusy,
    scannedBarcode,
    invalidBarcode,
    errorMessage,
  );
}

/// Owns the camera permission negotiation and barcode scanning flow state.
///
/// Views (`BarcodeScanScreen`, `BarcodeCameraGate`) watch this ViewModel and
/// dispatch user actions through it, keeping presentation completely decoupled
/// from direct `data/` imports and platform service calls.
class BarcodeScannerViewModel extends ViewModel<BarcodeScannerState> {
  BarcodeScannerViewModel({PermissionService? permissionService})
    : _overridePermissionService = permissionService;

  final PermissionService? _overridePermissionService;

  PermissionService get _permissions =>
      _overridePermissionService ?? ref.read(permissionServiceProvider);

  @override
  BarcodeScannerState buildOnce() => const BarcodeScannerState();

  /// Reads current camera permission without prompting the user.
  ///
  /// If already granted or platform outcome is unknown, transitions directly
  /// to [BarcodeCameraPermissionStatus.ready].
  /// If permanently denied/restricted, transitions to [BarcodeCameraPermissionStatus.blocked].
  /// Otherwise, immediately triggers [requestPermission].
  Future<void> checkPermission() async {
    state = state.copyWith(
      permissionStatus: BarcodeCameraPermissionStatus.asking,
      isBusy: true,
      clearError: true,
    );
    try {
      final snapshot = await _permissions.status(PermissionKind.camera);
      if (snapshot.isGranted || snapshot.outcome == PermissionOutcome.unknown) {
        state = state.copyWith(
          permissionStatus: BarcodeCameraPermissionStatus.ready,
          isBusy: false,
        );
        return;
      }
      if (snapshot.needsSystemSettings) {
        state = state.copyWith(
          permissionStatus: BarcodeCameraPermissionStatus.blocked,
          isBusy: false,
        );
        return;
      }
      await requestPermission();
    } catch (e) {
      state = state.copyWith(
        permissionStatus: BarcodeCameraPermissionStatus.error,
        isBusy: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// Requests camera permission from the platform OS dialog.
  Future<void> requestPermission() async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final result = await _permissions.request(PermissionKind.camera);
      if (result.isGranted || result.outcome == PermissionOutcome.unknown) {
        state = state.copyWith(
          permissionStatus: BarcodeCameraPermissionStatus.ready,
          isBusy: false,
        );
      } else if (result.needsSystemSettings) {
        state = state.copyWith(
          permissionStatus: BarcodeCameraPermissionStatus.blocked,
          isBusy: false,
        );
      } else {
        state = state.copyWith(
          permissionStatus: BarcodeCameraPermissionStatus.denied,
          isBusy: false,
        );
      }
    } catch (e) {
      state = state.copyWith(
        permissionStatus: BarcodeCameraPermissionStatus.error,
        isBusy: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// Re-checks camera permission after returning from system settings.
  Future<void> recheckPermission() async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final snapshot = await _permissions.status(PermissionKind.camera);
      if (snapshot.isGranted || snapshot.outcome == PermissionOutcome.unknown) {
        state = state.copyWith(
          permissionStatus: BarcodeCameraPermissionStatus.ready,
          isBusy: false,
        );
      } else if (snapshot.needsSystemSettings) {
        state = state.copyWith(
          permissionStatus: BarcodeCameraPermissionStatus.blocked,
          isBusy: false,
        );
      } else {
        state = state.copyWith(
          permissionStatus: BarcodeCameraPermissionStatus.denied,
          isBusy: false,
        );
      }
    } catch (e) {
      state = state.copyWith(
        permissionStatus: BarcodeCameraPermissionStatus.error,
        isBusy: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// Opens the device application settings page.
  Future<bool> openSystemSettings() async {
    try {
      return await _permissions.openSystemSettings();
    } catch (_) {
      return false;
    }
  }

  /// Validates and locks in a scanned barcode.
  ///
  /// Returns `true` if a barcode or validation failure was accepted, or `false`
  /// if ignored (empty or a code is already locked in).
  bool onBarcodeDetected(String raw) {
    final code = normalizeBarcode(raw);
    if (code.isEmpty) return false;
    if (state.scannedBarcode != null || state.invalidBarcode != null) {
      return false;
    }
    final reason = validateBarcode(code);
    if (reason != null) {
      state = state.copyWith(
        invalidBarcode: InvalidBarcode(code: code, reason: reason),
      );
      return true;
    }
    state = state.copyWith(scannedBarcode: code);
    return true;
  }

  /// Clears scanned/invalid codes to return to live scanning.
  void scanAnother() {
    state = state.copyWith(
      clearScannedBarcode: true,
      clearInvalidBarcode: true,
      clearError: true,
    );
  }

  /// Sets a camera runtime error message.
  void setCameraError(String? message) {
    state = state.copyWith(errorMessage: message);
  }

  /// Resets the full ViewModel state.
  void reset() {
    state = const BarcodeScannerState();
  }
}

/// Provider for [BarcodeScannerViewModel].
final barcodeScannerViewModelProvider =
    NotifierProvider<BarcodeScannerViewModel, BarcodeScannerState>(
      BarcodeScannerViewModel.new,
    );
