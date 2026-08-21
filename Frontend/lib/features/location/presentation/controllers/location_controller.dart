import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/location_repository.dart';
import '../../domain/models/user_location.dart';
import '../../../../core/storage/secure_storage_service.dart';

enum LocationStatus { initial, loading, success, permissionDenied, serviceDisabled, error }

class LocationState {
  final LocationStatus status;
  final UserLocation? location;
  final String? errorMessage;

  const LocationState({required this.status, this.location, this.errorMessage});

  factory LocationState.initial() => const LocationState(status: LocationStatus.initial);
}

final locationControllerProvider = NotifierProvider<LocationController, LocationState>(LocationController.new);

class LocationController extends Notifier<LocationState> {
  static const _locationKey = 'user_saved_location';

  @override
  LocationState build() {
    return LocationState.initial();
  }

  Future<void> loadSavedLocation() async {
    final storage = ref.read(secureStorageProvider);
    final locationJson = await storage.read(key: _locationKey);
    if (locationJson != null) {
      state = LocationState(
        status: LocationStatus.success,
        location: UserLocation.fromJson(jsonDecode(locationJson)),
      );
    }
  }

  Future<void> fetchCurrentLocation() async {
    state = const LocationState(status: LocationStatus.loading);

    try {
      final repository = ref.read(locationRepositoryProvider);
      final serviceEnabled = await repository.isLocationServiceEnabled();
      if (!serviceEnabled) {
        state = const LocationState(
          status: LocationStatus.serviceDisabled,
          errorMessage: 'GPS is turned off',
        );
        return;
      }

      final hasPermission = await repository.requestPermission();
      if (!hasPermission) {
        state = const LocationState(
          status: LocationStatus.permissionDenied,
          errorMessage: 'Location permission denied',
        );
        return;
      }

      final location = await repository.getCurrentLocation();
      await _saveLocation(location);
      state = LocationState(status: LocationStatus.success, location: location);
    } catch (e) {
      state = LocationState(status: LocationStatus.error, errorMessage: e.toString());
    }
  }

  Future<void> setManualLocation(UserLocation location) async {
    state = const LocationState(status: LocationStatus.loading);
    await _saveLocation(location);
    state = LocationState(status: LocationStatus.success, location: location);
  }

  Future<void> _saveLocation(UserLocation location) async {
    final storage = ref.read(secureStorageProvider);
    await storage.write(key: _locationKey, value: jsonEncode(location.toJson()));
  }
}