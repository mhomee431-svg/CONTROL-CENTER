import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_providers.dart';
import '../domain/holiday_models.dart';

/// Shop-holiday contract: list, add and remove scheduled closure days.
abstract class HolidayRepository {
  /// All holidays for the shop, backend-sorted by date (soonest first).
  Future<List<ShopHoliday>> list(int shopId, String token);

  /// Schedules one closure day. Backend takes query params (not a body).
  Future<void> add(int shopId, HolidayDraft draft, String token);

  /// Deletes one holiday. Fails with 404 when it was already removed.
  Future<void> remove(int shopId, int holidayId, String token);
}

class ApiHolidayRepository implements HolidayRepository {
  ApiHolidayRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<ShopHoliday>> list(int shopId, String token) async {
    final data = await _api.get(
      ApiEndpoints.shopHolidays('$shopId'),
      token: token,
    ) as Map<String, dynamic>;
    return ((data['holidays'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        // Per-row tolerance: a row the backend sends in a shape we cannot
        // represent is skipped, so one bad entry cannot blank the screen.
        .map(ShopHoliday.tryParse)
        .whereType<ShopHoliday>()
        .toList(growable: false);
  }

  @override
  Future<void> add(int shopId, HolidayDraft draft, String token) async {
    // The backend models the POST as query parameters — build the query
    // string explicitly so no parameter can be silently dropped.
    final query = <String>[
      'holiday_date=${draft.encodedDate}',
      if (draft.reason != null && draft.reason!.isNotEmpty)
        'reason=${Uri.encodeComponent(draft.reason!)}',
      'is_recurring_yearly=${draft.recurringYearly}',
    ].join('&');
    await _api.post(
      '${ApiEndpoints.shopHolidays('$shopId')}?$query',
      token: token,
    );
  }

  @override
  Future<void> remove(int shopId, int holidayId, String token) async {
    await _api.delete(
      ApiEndpoints.shopHoliday('$shopId', holidayId),
      token: token,
    );
  }
}

final holidayRepositoryProvider = Provider<HolidayRepository>((ref) {
  final api = ref.watch(apiClientProvider);
  return ApiHolidayRepository(api);
});
