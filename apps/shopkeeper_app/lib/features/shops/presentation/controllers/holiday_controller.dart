import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/token_store.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../data/holiday_repository.dart';
import '../../domain/holiday_models.dart';

/// Lifecycle of the holidays list.
enum HolidaysStatus { loading, ready, error, noShop }

class HolidaysState {
  const HolidaysState({
    required this.status,
    this.items = const [],
    this.message,
  });

  final HolidaysStatus status;
  final List<ShopHoliday> items;

  /// Error copy when [status] is [HolidaysStatus.error].
  final String? message;

  factory HolidaysState.loading() =>
      const HolidaysState(status: HolidaysStatus.loading);

  /// Holidays that still matter: yearly-recurring or not yet passed.
  List<ShopHoliday> get upcoming =>
      items.where((h) => h.isUpcoming).toList(growable: false);

  /// One-off closures whose date has passed — kept visible for records.
  List<ShopHoliday> get past =>
      items.where((h) => h.isPast).toList(growable: false);
}

/// THE single source of truth for the selected shop's holidays.
///
/// The settings screen renders this state and forwards intents; it never
/// keeps its own copy (no parallel cache list). Every mutation reloads from
/// the backend so the list can never drift from the server.
final holidaysControllerProvider =
    NotifierProvider<HolidaysController, HolidaysState>(
        HolidaysController.new);

class HolidaysController extends Notifier<HolidaysState> {
  @override
  HolidaysState build() => HolidaysState.loading();

  HolidayRepository get _repo => ref.read(holidayRepositoryProvider);

  int? get _shopId => ref.read(selectedShopProvider)?.id;

  /// Loads every holiday for the selected shop (soonest first).
  Future<void> load() async {
    final shopId = _shopId;
    if (shopId == null) {
      state = const HolidaysState(
        status: HolidaysStatus.noShop,
        message: 'No shop selected',
      );
      return;
    }
    state = HolidaysState.loading();
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) throw const ApiException(message: 'Not signed in');
      final items = await _repo.list(shopId, token);
      state = HolidaysState(status: HolidaysStatus.ready, items: items);
    } on ApiException catch (e) {
      state = HolidaysState(
        status: HolidaysStatus.error,
        message: _friendly(e),
      );
    } catch (_) {
      state = const HolidaysState(
        status: HolidaysStatus.error,
        message: 'Could not load holidays.',
      );
    }
  }

  /// Schedules one closure day. Returns true on success — the list is
  /// re-fetched from the backend so both slices (upcoming/past) refresh.
  Future<bool> add(HolidayDraft draft) async {
    final shopId = _shopId;
    if (shopId == null) {
      state = const HolidaysState(
        status: HolidaysStatus.error,
        message: 'No shop selected',
      );
      return false;
    }
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) throw const ApiException(message: 'Not signed in');
      await _repo.add(shopId, draft, token);
      await load();
      return true;
    } on ApiException catch (e) {
      state = HolidaysState(
        status: HolidaysStatus.error,
        message: _friendly(e),
      );
      return false;
    } catch (_) {
      state = const HolidaysState(
        status: HolidaysStatus.error,
        message: 'Could not add the holiday. Please retry.',
      );
      return false;
    }
  }

  /// Deletes one holiday and re-syncs the list with the backend.
  Future<bool> remove(int holidayId) async {
    final shopId = _shopId;
    if (shopId == null) return false;
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) throw const ApiException(message: 'Not signed in');
      await _repo.remove(shopId, holidayId, token);
      await load();
      return true;
    } on ApiException catch (e) {
      state = HolidaysState(status: HolidaysStatus.error, message: _friendly(e));
      return false;
    } catch (_) {
      state = const HolidaysState(
        status: HolidaysStatus.error,
        message: 'Could not remove the holiday. Please retry.',
      );
      return false;
    }
  }

  /// Technical exceptions → shopkeeper-friendly copy (offers-style).
  String _friendly(ApiException e) {
    if (e.isUnauthorized || e.statusCode == 401) {
      return 'Your session has expired. Please sign in again.';
    }
    if (e.isForbidden || e.statusCode == 403) {
      return 'Only shop owners can manage holidays.';
    }
    if (e.statusCode == null) {
      return 'No internet connection. Check your network and retry.';
    }
    return e.message;
  }
}
