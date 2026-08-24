import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/location_repository.dart';
import '../../domain/models/location_exception.dart';
import '../../domain/models/location_permission_status.dart';
import '../../domain/models/saved_address.dart';
import '../../domain/models/user_location.dart';
import '../../../../core/storage/secure_storage_service.dart';

/// High-level location lifecycle states.
enum LocationStatus {
  /// No location has been loaded yet (app just started).
  initial,

  /// A location request is in progress.
  loading,

  /// A valid location is available.
  success,

  /// User denied permission (can be asked again).
  permissionDenied,

  /// User permanently denied permission (must use system settings).
  permissionPermanentlyDenied,

  /// GPS / location service is disabled on the device.
  serviceDisabled,

  /// A generic error occurred (network, invalid coords, etc.).
  error,
}

class LocationState {
  final LocationStatus status;
  final UserLocation? location;
  final String? errorMessage;
  final LocationPermissionStatus permissionStatus;
  final bool isRefreshing;

  const LocationState({
    required this.status,
    this.location,
    this.errorMessage,
    this.permissionStatus = LocationPermissionStatus.unknown,
    this.isRefreshing = false,
  });

  factory LocationState.initial() =>
      const LocationState(status: LocationStatus.initial);

  factory LocationState.loading() =>
      const LocationState(status: LocationStatus.loading);

  factory LocationState.success(UserLocation location) =>
      LocationState(
        status: LocationStatus.success,
        location: location,
        permissionStatus: LocationPermissionStatus.granted,
      );

  factory LocationState.permissionDenied() =>
      const LocationState(
        status: LocationStatus.permissionDenied,
        permissionStatus: LocationPermissionStatus.denied,
        errorMessage: 'Location permission denied. Please allow access to find nearby shops.',
      );

  factory LocationState.permissionPermanentlyDenied() =>
      const LocationState(
        status: LocationStatus.permissionPermanentlyDenied,
        permissionStatus: LocationPermissionStatus.permanentlyDenied,
        errorMessage: 'Location permission is permanently denied. Please enable it in your device settings.',
      );

  factory LocationState.serviceDisabled() =>
      const LocationState(
        status: LocationStatus.serviceDisabled,
        errorMessage: 'Location services are turned off. Please enable GPS to find nearby shops.',
      );

  factory LocationState.error(String message) =>
      LocationState(status: LocationStatus.error, errorMessage: message);
}

final locationControllerProvider =
    NotifierProvider<LocationController, LocationState>(LocationController.new);

class LocationController extends Notifier<LocationState> {
  static const _locationKey = 'user_saved_location';
  static const _savedAddressesKey = 'user_saved_addresses';
  static const _lastFetchKey = 'last_location_fetch_ms';

  /// Minimum interval between automatic location refreshes (5 minutes).
  static const _minRefreshIntervalMs = 5 * 60 * 1000;

  @override
  LocationState build() {
    return LocationState.initial();
  }

  // ── Persistence ─────────────────────────────────────────────────────

  /// Restore the saved location and saved addresses on app startup.
  Future<void> loadSavedLocation() async {
    final storage = ref.read(secureStorageProvider);
    final locationJson = await storage.read(key: _locationKey);
    if (locationJson != null) {
      try {
        final location = UserLocation.fromJson(jsonDecode(locationJson));
        state = LocationState.success(location);
      } catch (_) {
        // Corrupt data — ignore and let the user re-select.
      }
    }
  }

  /// Loads the list of saved customer addresses.
  Future<List<SavedAddress>> loadSavedAddresses() async {
    final storage = ref.read(secureStorageProvider);
    final json = await storage.read(key: _savedAddressesKey);
    if (json == null) return [];

    try {
      final list = jsonDecode(json) as List;
      return list
          .map((e) => SavedAddress.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Persists the list of saved customer addresses.
  Future<void> _saveAddresses(List<SavedAddress> addresses) async {
    final storage = ref.read(secureStorageProvider);
    await storage.write(
      key: _savedAddressesKey,
      value: jsonEncode(addresses.map((a) => a.toJson()).toList()),
    );
  }

  /// Saves a new address to the customer's saved list.
  Future<void> saveAddress({
    required String label,
    required UserLocation location,
  }) async {
    final addresses = await loadSavedAddresses();
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final address = SavedAddress.create(
      id: id,
      label: label,
      location: location,
      savedAt: DateTime.now(),
    );
    addresses.add(address);
    await _saveAddresses(addresses);
  }

  /// Removes a saved address by ID.
  Future<void> removeSavedAddress(String id) async {
    final addresses = await loadSavedAddresses();
    addresses.removeWhere((a) => a.id == id);
    await _saveAddresses(addresses);
  }

  /// Selects a saved address as the current location.
  Future<void> selectSavedAddress(SavedAddress address) async {
    final selected = address.select();
    await _saveLocation(selected.location);
    state = LocationState.success(selected.location);
  }

  // ── Location retrieval ──────────────────────────────────────────────

  /// Fetches the current device location.
  ///
  /// Throttles repeated calls: if a location was fetched within
  /// [_minRefreshInterval], the saved location is returned instead of
  /// triggering a new GPS request.
  Future<void> fetchCurrentLocation({bool force = false}) async {
    // Throttle: don't request location repeatedly without reason.
    if (!force && await _isRecentlyFetched()) {
      final saved = await _readSavedLocation();
      if (saved != null) {
        state = LocationState.success(saved);
        return;
      }
    }

    state = LocationState.loading();

    try {
      final repository = ref.read(locationRepositoryProvider);

      final serviceEnabled = await repository.isLocationServiceEnabled();
      if (!serviceEnabled) {
        state = LocationState.serviceDisabled();
        return;
      }

      final permission = await repository.requestPermission();
      switch (permission) {
        case LocationPermissionStatus.permanentlyDenied:
          state = LocationState.permissionPermanentlyDenied();
          return;
        case LocationPermissionStatus.denied:
        case LocationPermissionStatus.restricted:
          state = LocationState.permissionDenied();
          return;
        case LocationPermissionStatus.unknown:
          // Unknown permission — try to get location anyway; the
          // repository will throw a LocationException if it fails.
          break;
        case LocationPermissionStatus.granted:
          break;
      }

      final location = await repository.getCurrentLocation();

      // Handle approximate/invalid locations appropriately.
      if (!location.hasValidCoordinates) {
        state = LocationState.error('Received invalid coordinates from GPS.');
        return;
      }

      if (location.isApproximate) {
        // We have coordinates but no reverse-geocoded address.
        // Still usable for PostGIS distance queries, but mark it.
        state = LocationState.success(location);
        await _saveLocation(location);
        await _markFetched();
        return;
      }

      await _saveLocation(location);
      await _markFetched();
      state = LocationState.success(location);
    } on LocationException catch (e) {
      switch (e.type) {
        case LocationErrorType.permissionPermanentlyDenied:
          state = LocationState.permissionPermanentlyDenied();
          break;
        case LocationErrorType.permissionDenied:
        case LocationErrorType.permissionRestricted:
          state = LocationState.permissionDenied();
          break;
        case LocationErrorType.serviceDisabled:
          state = LocationState.serviceDisabled();
          break;
        default:
          state = LocationState.error(e.message);
      }
    } catch (e) {
      state = LocationState.error(e.toString());
    }
  }

  /// Refreshes the current location, bypassing the throttle.
  Future<void> refreshLocation() async {
    await fetchCurrentLocation(force: true);
  }

  /// Retries the last failed location request.
  Future<void> retry() async {
    await fetchCurrentLocation(force: true);
  }

  /// Sets a manually selected location.
  Future<void> setManualLocation(UserLocation location) async {
    state = LocationState.loading();
    final selected = location.select();
    await _saveLocation(selected);
    await _markFetched();
    state = LocationState.success(selected);
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  Future<bool> _isRecentlyFetched() async {
    final storage = ref.read(secureStorageProvider);
    final lastFetch = await storage.read(key: _lastFetchKey);
    if (lastFetch == null) return false;
    final lastMs = int.tryParse(lastFetch) ?? 0;
    return DateTime.now().millisecondsSinceEpoch - lastMs < _minRefreshIntervalMs;
  }

  Future<void> _markFetched() async {
    final storage = ref.read(secureStorageProvider);
    await storage.write(
      key: _lastFetchKey,
      value: DateTime.now().millisecondsSinceEpoch.toString(),
    );
  }

  Future<UserLocation?> _readSavedLocation() async {
    final storage = ref.read(secureStorageProvider);
    final locationJson = await storage.read(key: _locationKey);
    if (locationJson == null) return null;
    try {
      return UserLocation.fromJson(jsonDecode(locationJson));
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveLocation(UserLocation location) async {
    final storage = ref.read(secureStorageProvider);
    await storage.write(key: _locationKey, value: jsonEncode(location.toJson()));
  }
}