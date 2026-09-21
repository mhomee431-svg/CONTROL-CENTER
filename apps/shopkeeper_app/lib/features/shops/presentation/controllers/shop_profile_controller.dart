import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/token_store.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../data/location_accuracy_config.dart';
import '../../data/location_service.dart';
import '../../data/shop_repository.dart';
import '../../domain/shop_models.dart';

/// Injectable location service (tests override with a fake position source).
final shopLocationServiceProvider = Provider<LocationService>(
  (ref) => LocationService(),
);

// ── Shop detail (module SSOT) ────────────────────────────────────────────────

enum ShopProfileStatus { loading, ready, noShop, error }

class ShopProfileState {
  const ShopProfileState({required this.status, this.detail, this.message});

  final ShopProfileStatus status;
  final ShopDetail? detail;
  final String? message;

  bool get isReady => status == ShopProfileStatus.ready && detail != null;
}

/// Loads the selected shop's detail for the whole Shop Profile module — the
/// hub, Business Information, Business Category, Shop Location and Shop Status
/// screens all render slices of ONE payload instead of refetching per screen.
final shopProfileDetailProvider =
    NotifierProvider<ShopProfileDetailController, ShopProfileState>(
      ShopProfileDetailController.new,
    );

class ShopProfileDetailController extends Notifier<ShopProfileState> {
  @override
  ShopProfileState build() =>
      const ShopProfileState(status: ShopProfileStatus.loading);

  ShopRepository get _repo => ref.read(shopRepositoryProvider);

  Future<String> _token() async {
    final token = await ref.read(tokenStoreProvider).readAccessToken();
    if (token == null) throw const ApiException(message: 'Not signed in');
    return token;
  }

  Future<void> load() async {
    final shop = ref.read(selectedShopProvider);
    if (shop == null) {
      state = const ShopProfileState(status: ShopProfileStatus.noShop);
      return;
    }
    state = const ShopProfileState(status: ShopProfileStatus.loading);
    try {
      final detail = await _repo.getShopDetail(shop.id, await _token());
      state = ShopProfileState(status: ShopProfileStatus.ready, detail: detail);
    } on ApiException catch (e) {
      state = ShopProfileState(
        status: ShopProfileStatus.error,
        message: e.message,
      );
    } catch (_) {
      state = const ShopProfileState(
        status: ShopProfileStatus.error,
        message: 'Could not load the shop profile.',
      );
    }
  }

  /// Applies the shopkeeper's profile edits and reloads the authoritative
  /// payload. Returns true on success; failures land in [ShopProfileState.message].
  Future<bool> saveProfileFields(Map<String, dynamic> fields) async {
    final shop = ref.read(selectedShopProvider);
    if (shop == null) return false;
    try {
      await _repo.updateShopProfile(shop.id, fields, await _token());
      await load();
      return true;
    } on ApiException catch (e) {
      state = ShopProfileState(
        status: ShopProfileStatus.error,
        detail: state.detail,
        message: e.message,
      );
      return false;
    } catch (_) {
      state = ShopProfileState(
        status: ShopProfileStatus.error,
        detail: state.detail,
        message: 'Update failed. Please retry.',
      );
      return false;
    }
  }
}

// ── Weekly operating hours ───────────────────────────────────────────────────

enum ShopHoursStatus { loading, ready, saving, error }

class ShopHoursState {
  const ShopHoursState({
    required this.status,
    this.hours = const <ShopHourEntry>[],
    this.message,
  });

  final ShopHoursStatus status;
  final List<ShopHourEntry> hours;

  /// Validation / failure copy — cleared by the screen after showing it.
  final String? message;

  /// True while a save request is in flight (status == [saving]).
  bool get isSaving => status == ShopHoursStatus.saving;
}

/// The shop's weekly schedule, edited in place and saved as ONE server call.
final shopHoursProvider = NotifierProvider<ShopHoursController, ShopHoursState>(
  ShopHoursController.new,
);

class ShopHoursController extends Notifier<ShopHoursState> {
  @override
  ShopHoursState build() =>
      const ShopHoursState(status: ShopHoursStatus.loading);

  ShopRepository get _repo => ref.read(shopRepositoryProvider);

  Future<String> _token() async {
    final token = await ref.read(tokenStoreProvider).readAccessToken();
    if (token == null) throw const ApiException(message: 'Not signed in');
    return token;
  }

  Future<void> load() async {
    final shop = ref.read(selectedShopProvider);
    if (shop == null) {
      state = const ShopHoursState(
        status: ShopHoursStatus.error,
        message: 'No shop selected',
      );
      return;
    }
    state = const ShopHoursState(status: ShopHoursStatus.loading);
    try {
      final hours = await _repo.fetchOperatingHours(shop.id, await _token());
      state = ShopHoursState(
        status: ShopHoursStatus.ready,
        // The editor always shows all 7 days, server rows or defaults.
        hours: ShopHourEntry.normalizeWeek(hours),
      );
    } on ApiException catch (e) {
      state = ShopHoursState(status: ShopHoursStatus.error, message: e.message);
    } catch (_) {
      state = const ShopHoursState(
        status: ShopHoursStatus.error,
        message: 'Could not load the operating hours.',
      );
    }
  }

  /// Applies a local edit to one day. Never touches the server.
  void updateEntry(ShopHourEntry entry) {
    state = ShopHoursState(
      status: state.status,
      hours: [
        for (final hour in state.hours)
          hour.dayOfWeek == entry.dayOfWeek ? entry : hour,
      ],
    );
  }

  /// Sends the whole week. Returns true on success; validation errors and
  /// transport failures land in [ShopHoursState.message] instead of throwing.
  Future<bool> save() async {
    final shop = ref.read(selectedShopProvider);
    if (shop == null || state.isSaving) return false;

    // Client-side sanity: an open day needs open < close (the server rejects
    // the whole request otherwise).
    for (final hour in state.hours) {
      if (hour.isClosed) continue;
      final open = _minutes(hour.openTime);
      final close = _minutes(hour.closeTime);
      if (open == null || close == null || close <= open) {
        state = ShopHoursState(
          status: ShopHoursStatus.ready,
          hours: state.hours,
          message: '${hour.dayLabel}: closing time must be after opening time.',
        );
        return false;
      }
    }

    state = ShopHoursState(status: ShopHoursStatus.saving, hours: state.hours);
    try {
      await _repo.saveOperatingHours(
        shopId: shop.id,
        hours: state.hours,
        token: await _token(),
      );
      // Re-read the authoritative week (the server may normalise times).
      await load();
      return true;
    } on ApiException catch (e) {
      state = ShopHoursState(
        status: ShopHoursStatus.ready,
        hours: state.hours,
        message: e.message,
      );
      return false;
    } catch (_) {
      state = ShopHoursState(
        status: ShopHoursStatus.ready,
        hours: state.hours,
        message: 'Could not save the operating hours. Please retry.',
      );
      return false;
    }
  }

  /// Called by the screen once a message has been surfaced, so a rebuild
  /// never re-shows it.
  void clearMessage() {
    if (state.message != null) {
      state = ShopHoursState(status: state.status, hours: state.hours);
    }
  }

  static int? _minutes(String? time) {
    if (time == null) return null;
    final parts = time.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }
}

// ── Shop location (view + controlled edit) ──────────────────────────────────

enum ShopLocationStatus { loading, ready, saving, error }

class ShopLocationState {
  const ShopLocationState({
    required this.status,
    this.detail,
    this.message,
    this.savedMessage,
  });

  final ShopLocationStatus status;
  final ShopDetail? detail;

  /// True while the GPS→server update is in flight (status == [saving]).
  bool get isSaving => status == ShopLocationStatus.saving;

  /// Validation / failure copy.
  final String? message;

  /// One-shot success copy — cleared by the screen after showing it.
  final String? savedMessage;
}

/// Shop Location: reads the stored coordinates and owns the controlled
/// "use my current location" edit (`PATCH /shops/{id}/location`), the same
/// IDOR-safe endpoint the backend audits.
final shopLocationProvider =
    NotifierProvider<ShopLocationController, ShopLocationState>(
      ShopLocationController.new,
    );

class ShopLocationController extends Notifier<ShopLocationState> {
  @override
  ShopLocationState build() =>
      const ShopLocationState(status: ShopLocationStatus.loading);

  ShopRepository get _repo => ref.read(shopRepositoryProvider);

  Future<String> _token() async {
    final token = await ref.read(tokenStoreProvider).readAccessToken();
    if (token == null) throw const ApiException(message: 'Not signed in');
    return token;
  }

  Future<void> load() async {
    final shop = ref.read(selectedShopProvider);
    if (shop == null) {
      state = const ShopLocationState(
        status: ShopLocationStatus.error,
        message: 'No shop selected',
      );
      return;
    }
    state = const ShopLocationState(status: ShopLocationStatus.loading);
    try {
      final detail = await _repo.getShopDetail(shop.id, await _token());
      state = ShopLocationState(
        status: ShopLocationStatus.ready,
        detail: detail,
      );
    } on ApiException catch (e) {
      state = ShopLocationState(
        status: ShopLocationStatus.error,
        message: e.message,
      );
    } catch (_) {
      state = const ShopLocationState(
        status: ShopLocationStatus.error,
        message: 'Could not load the shop location.',
      );
    }
  }

  /// Acquires the device's best GPS fix, checks it against the shop's accuracy
  /// contract and persists it. Returns true when the location was saved.
  ///
  /// A too-imprecise fix or a missing permission is reported through
  /// [ShopLocationState.message] — the stored location is never overwritten.
  Future<bool> useCurrentLocation() async {
    final shop = ref.read(selectedShopProvider);
    if (shop == null || state.isSaving) return false;

    final service = ref.read(shopLocationServiceProvider);
    final permission = await service.resolvePermission();
    if (!permission.granted) {
      state = _keep(
        message: permission.deniedForever
            ? 'Location permission is turned off for this app. Enable it in '
                  'your device settings and try again.'
            : 'Location permission is needed to update the shop location.',
      );
      return false;
    }

    state = const ShopLocationState(status: ShopLocationStatus.saving);
    try {
      final acquisition = await service.acquireBestLocation(
        timeout: const Duration(seconds: 20),
      );
      final reading = acquisition.best;
      if (reading == null || !reading.hasValidCoordinates) {
        state = _keep(
          message:
              'Could not get a location fix. Step outside or try again '
              'near a window.',
        );
        return false;
      }
      final accuracy = reading.accuracy ?? double.infinity;
      if (accuracy > LocationAccuracyConfig.minimumUsableAccuracyMeters) {
        state = _keep(
          message:
              'The location fix is only accurate to '
              '${accuracy.toStringAsFixed(0)} m. Move to a clearer spot '
              '(under ${LocationAccuracyConfig.minimumUsableAccuracyMeters.toStringAsFixed(0)} m) and retry.',
        );
        return false;
      }
      await _repo.updateShopLocation(shop.id, {
        'latitude': reading.latitude,
        'longitude': reading.longitude,
        'location': {
          'location_source': 'GPS',
          'location_type': 'SHOP_ENTRANCE',
          'location_status': 'CONFIRMED',
          'accuracy_meters': accuracy,
          'location_captured_at': DateTime.now().toUtc().toIso8601String(),
        },
      }, await _token());
      await load();
      state = ShopLocationState(
        status: ShopLocationStatus.ready,
        detail: state.detail,
        savedMessage:
            'Shop location updated '
            '(${accuracy.toStringAsFixed(0)} m accuracy).',
      );
      return true;
    } on ApiException catch (e) {
      state = _keep(message: e.message);
      return false;
    } catch (_) {
      state = _keep(
        message: 'Could not update the shop location. Please retry.',
      );
      return false;
    }
  }

  /// Called by the screen once the success snackbar has been shown, so a
  /// rebuild never re-shows it.
  void clearSavedMessage() {
    if (state.savedMessage != null) {
      state = ShopLocationState(
        status: state.status,
        detail: state.detail,
        message: state.message,
      );
    }
  }

  /// Rebuilds the state while keeping the loaded payload — a failed action
  /// must never blank the screen.
  ShopLocationState _keep({String? message}) => ShopLocationState(
    status: ShopLocationStatus.ready,
    detail: state.detail,
    message: message,
    savedMessage: state.savedMessage,
  );
}
