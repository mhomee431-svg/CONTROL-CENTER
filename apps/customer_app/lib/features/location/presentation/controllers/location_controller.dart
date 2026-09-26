import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/security/safe_logger.dart';
import '../../../../core/storage/secure_storage_service.dart';
import '../../domain/location_repository.dart';
import '../../domain/models/location_exception.dart';
import '../../domain/models/location_permission_status.dart';
import '../../domain/models/saved_address.dart';
import '../../domain/models/user_location.dart';

enum LocationStatus {
  initial,
  loading,
  success,
  permissionDenied,
  permissionPermanentlyDenied,
  serviceDisabled,
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
  factory LocationState.success(UserLocation location) => LocationState(
    status: LocationStatus.success,
    location: location,
    permissionStatus: LocationPermissionStatus.granted,
  );
  factory LocationState.permissionDenied() => const LocationState(
    status: LocationStatus.permissionDenied,
    permissionStatus: LocationPermissionStatus.denied,
    errorMessage:
        'Location permission denied. Please allow access to find nearby shops.',
  );
  factory LocationState.permissionPermanentlyDenied() => const LocationState(
    status: LocationStatus.permissionPermanentlyDenied,
    permissionStatus: LocationPermissionStatus.permanentlyDenied,
    errorMessage: 'Location permission is permanently denied. Please enable it in your device settings.',
  );
  factory LocationState.serviceDisabled() => const LocationState(
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
  static const _recentLocationsKey = 'user_recent_locations';
  static const _minRefreshIntervalMs = 5 * 60 * 1000;

  /// Most-recent-first cap for the recent-locations strip.
  static const int maxRecentLocations = 5;

  /// Coordinates closer than this (degrees, ~11 m) are treated as the same
  /// place so re-picking one spot does not flood the list.
  static const double _dedupeEpsilon = 0.0001;

  @override
  LocationState build() => LocationState.initial();

  /// Loads the saved location from secure storage into the state (if any).
  Future<void> loadSavedLocation() async {
    final saved = await _readSavedLocation();
    if (saved != null) {
      state = LocationState.success(saved);
    }
  }

  // ── Recent locations ────────────────────────────────────────────────────

  /// Recently used locations, most recent first (deduped, capped).
  Future<List<UserLocation>> loadRecentLocations() async {
    final raw = await _storage().read(key: _recentLocationsKey);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(UserLocation.fromJson)
          .where((location) => location.hasValidCoordinates)
          .toList();
    } catch (_) {
      // Corrupt payload — treat as empty rather than crashing the UI.
      return const [];
    }
  }

  /// Records [location] as the most recent one, then persists the list.
  Future<List<UserLocation>> recordRecentLocation(UserLocation location) async {
    if (!location.hasValidCoordinates) return loadRecentLocations();

    final existing = await loadRecentLocations();
    final deduped = <UserLocation>[
      location,
      for (final previous in existing)
        if (!_isSamePlace(previous, location)) previous,
    ];
    final capped = deduped.take(maxRecentLocations).toList();

    try {
      await _storage().write(
        key: _recentLocationsKey,
        value: jsonEncode(capped.map((l) => l.toJson()).toList()),
      );
    } catch (_) {
      // Recent locations are a convenience; never fail the selection flow.
    }
    return capped;
  }

  /// Wipes the recent-locations history (e.g. from Settings → clear history).
  Future<void> clearRecentLocations() async {
    try {
      await _storage().delete(key: _recentLocationsKey);
    } catch (_) {
      // Best effort — the strip is non-critical.
    }
  }

  static bool _isSamePlace(UserLocation a, UserLocation b) =>
      (a.latitude - b.latitude).abs() < _dedupeEpsilon &&
      (a.longitude - b.longitude).abs() < _dedupeEpsilon;

  SecureStorageService _storage() => ref.read(secureStorageProvider);

  Future<void> fetchCurrentLocation({bool force = false}) async {
    SafeLogger.debug('Location fetch requested; force=$force');
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

      // Check location services (GPS) are on first - prompts to enable if off.
      final serviceEnabled = await repository.isLocationServiceEnabled();
      SafeLogger.debug('Location service enabled=$serviceEnabled');
      if (!serviceEnabled) {
        state = LocationState.serviceDisabled();
        return;
      }

      final permission = await repository.requestPermission();
      SafeLogger.debug('Location permission status=$permission');
      switch (permission) {
        case LocationPermissionStatus.permanentlyDenied:
          state = LocationState.permissionPermanentlyDenied();
          return;
        case LocationPermissionStatus.denied:
        case LocationPermissionStatus.restricted:
          state = LocationState.permissionDenied();
          return;
        case LocationPermissionStatus.unknown:
        case LocationPermissionStatus.granted:
          break;
      }
      final location = await repository.getCurrentLocation();
      if (!location.hasValidCoordinates) {
        state = LocationState.error('Received invalid coordinates from GPS.');
        return;
      }
      await _saveLocation(location);
      await _markFetched();
      state = LocationState.success(location);
      await recordRecentLocation(location);
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
    } catch (e, stack) {
      SafeLogger.error('Location fetch failed.', e, stack);
      state = LocationState.error(e.toString());
    }
  }

  Future<void> refreshLocation() async => fetchCurrentLocation(force: true);
  Future<void> retry() async => fetchCurrentLocation(force: true);

  Future<void> setManualLocation(UserLocation location) async {
    state = LocationState.loading();
    final selected = location.select();
    await _saveLocation(selected);
    await _markFetched();
    state = LocationState.success(selected);
    await recordRecentLocation(selected);
  }

  Future<List<SavedAddress>> loadSavedAddresses() async {
    final storage = ref.read(secureStorageProvider);
    final json = await storage.read(key: _savedAddressesKey);
    if (json == null) return [];
    try {
      return (jsonDecode(json) as List)
          .map((e) => SavedAddress.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAddress({
    required String label,
    required UserLocation location,
  }) async {
    final addresses = await loadSavedAddresses();
    addresses.add(
      SavedAddress.create(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        label: label,
        location: location,
        savedAt: DateTime.now(),
      ),
    );
    await _saveAddresses(addresses);
  }

  Future<void> _saveAddresses(List<SavedAddress> addresses) async {
    final storage = ref.read(secureStorageProvider);
    await storage.write(
      key: _savedAddressesKey,
      value: jsonEncode(addresses.map((a) => a.toJson()).toList()),
    );
  }

  Future<void> removeSavedAddress(String id) async {
    final addresses = await loadSavedAddresses();
    addresses.removeWhere((a) => a.id == id);
    await _saveAddresses(addresses);
  }

  Future<void> selectSavedAddress(SavedAddress address) async {
    final selected = address.select();
    await _saveLocation(selected.location);
    state = LocationState.success(selected.location);
    await recordRecentLocation(selected.location);
  }

  Future<bool> _isRecentlyFetched() async {
    final storage = ref.read(secureStorageProvider);
    final f = await storage.read(key: _lastFetchKey);
    if (f == null) return false;
    return DateTime.now().millisecondsSinceEpoch - (int.tryParse(f) ?? 0) <
        _minRefreshIntervalMs;
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
    final j = await storage.read(key: _locationKey);
    if (j == null) return null;
    try {
      return UserLocation.fromJson(jsonDecode(j));
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveLocation(UserLocation location) async {
    final storage = ref.read(secureStorageProvider);
    await storage.write(
      key: _locationKey,
      value: jsonEncode(location.toJson()),
    );
  }
}
