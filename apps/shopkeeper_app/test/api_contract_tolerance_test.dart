import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/domain/import_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/notifications/domain/notification_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/domain/holiday_models.dart';

/// API-CONTRACT tolerance, pinned against the REAL parsers.
///
/// The backend owns every response shape; the app only maps what it actually
/// sends. These tests assert the four failure modes a contract can throw at a
/// client, so a schema change degrades instead of crashing:
///
///  * **nullable fields** — a null arrives where a value was expected;
///  * **missing optional fields** — a key is absent entirely;
///  * **enum additions** — the server starts sending a value we don't know;
///  * **unknown values** — anything else unrecognised.
///
/// The holiday rows below are copied from the real payload built in
/// `backend/app/api/routes/shopkeeper_extra.py` (`GET /shops/{id}/holidays`),
/// so the field names are the contract's, not invented ones.
void main() {
  /// Exactly what `shopkeeper_extra.py` puts on the wire.
  ///
  /// The `?` markers are the lint-preferred null-aware map entries: a null
  /// argument omits the key entirely, which is how each "missing optional
  /// field" case below is produced.
  Map<String, dynamic> backendHolidayRow({
    Object? id = 7,
    Object? holidayDate = '2026-01-12',
    Object? reason = 'Diwali',
    Object? recurring = true,
  }) => {
        'id': ?id,
        'holiday_date': ?holidayDate,
        'reason': ?reason,
        'is_recurring_yearly': ?recurring,
      };

  /// The repository's exact mapping: tolerant per row, so a single bad entry
  /// can never blank the screen.
  List<ShopHoliday> parseRows(List<Map<String, dynamic>> rows) => rows
      .map(ShopHoliday.tryParse)
      .whereType<ShopHoliday>()
      .toList(growable: false);

  group('backend DTO → ShopHoliday (field names are the contract’s)', () {
    test('the real payload row maps field for field', () {
      final holiday = ShopHoliday.tryParse(backendHolidayRow());

      expect(holiday, isNotNull);
      expect(holiday!.id, 7);
      expect(holiday.date, DateTime.parse('2026-01-12'));
      expect(holiday.reason, 'Diwali');
      expect(holiday.isRecurringYearly, isTrue);
    });

    test('nullable + missing optionals degrade, never throw', () {
      // `reason` is a nullable column — the backend sends null.
      final nullReason =
          ShopHoliday.tryParse(backendHolidayRow(reason: null, recurring: null));
      expect(nullReason, isNotNull);
      expect(nullReason!.reason, isNull);
      expect(nullReason.isRecurringYearly, isFalse);

      // …and the key can be absent entirely.
      final absent = ShopHoliday.tryParse(
        backendHolidayRow(reason: null, recurring: null),
      );
      expect(absent!.reason, isNull);
      expect(absent.isRecurringYearly, isFalse);
    });

    test('a timestamp date parses too (server uses str(date))', () {
      final holiday = ShopHoliday.tryParse(
        backendHolidayRow(holidayDate: '2026-01-12 00:00:00'),
      );

      expect(holiday, isNotNull);
      expect(holiday!.date.year, 2026);
      expect(holiday.date.month, 1);
      expect(holiday.date.day, 12);
    });
  });

  group('unrepresentable rows are skipped, not invented', () {
    test('a row with no id cannot be acted on and is dropped', () {
      expect(ShopHoliday.tryParse(backendHolidayRow(id: null)), isNull);
    });

    test('a missing, empty or malformed date is dropped', () {
      expect(ShopHoliday.tryParse(backendHolidayRow(holidayDate: null)), isNull);
      expect(ShopHoliday.tryParse(backendHolidayRow(holidayDate: '')), isNull);
      expect(
        ShopHoliday.tryParse(backendHolidayRow(holidayDate: 'not-a-date')),
        isNull,
      );
      expect(ShopHoliday.tryParse(backendHolidayRow(holidayDate: 42)), isNull);
    });

    test('one bad row never takes the good rows down with it', () {
      final holidays = parseRows([
        backendHolidayRow(id: 1, holidayDate: '2026-01-12'),
        backendHolidayRow(id: null), // unusable
        backendHolidayRow(id: 3, holidayDate: 'garbage'), // unusable
        backendHolidayRow(id: 4, holidayDate: '2026-03-01'),
      ]);

      expect(holidays.map((h) => h.id), [1, 4]);
    });

    test('an empty list is a valid, non-throwing response', () {
      expect(parseRows(const []), isEmpty);
    });
  });

  group('enum additions & unknown values render instead of crashing', () {
    test('a brand-new stock status is humanised, never thrown', () {
      // The server adds a state we have never seen.
      final added = StockStateView.of('AWAITING_RESTOCK');

      expect(added.label, 'Awaiting Restock');
      expect(added.value, 'AWAITING_RESTOCK');
      expect(added.isInStock, isFalse);
      expect(added.isOutOfStock, isFalse);
    });

    test('known aliases still collapse onto one canonical state', () {
      expect(StockStateView.of('PRE_ORDER'), StockStateView.inStock);
      expect(StockStateView.of('LIMITED_STOCK'), StockStateView.lowStock);
      expect(StockStateView.of('BACK_ORDER'), StockStateView.lowStock);
      // Legacy misspelling from an older payload.
      expect(StockStateView.of('DISCONTINUOUS'), StockStateView.discontinued);
    });

    test('absent / empty / null stock status is Unknown, not a crash', () {
      expect(StockStateView.of(null), StockStateView.unknown);
      expect(StockStateView.of(''), StockStateView.unknown);
      expect(StockStateView.of('   '), StockStateView.unknown);
    });

    test('an unknown notification type resolves to null, never throws', () {
      expect(NotificationCategory.of('BRAND_NEW_TYPE'), isNull);
      expect(NotificationCategory.of(''), isNull);
      // Known types still resolve, case-insensitively.
      expect(NotificationCategory.of('inventory_low'), NotificationCategory.inventory);
      expect(NotificationCategory.of('SYSTEM'), NotificationCategory.system);
    });

    test('an unknown import status still gets a readable label', () {
      expect(ImportJobStatusValue.label('BRAND_NEW_STATUS'), 'Brand new status');
      expect(ImportJobStatusValue.label(''), 'Unknown');
      // …and unknown values are never mistaken for a terminal outcome.
      expect(ImportJobStatusValue.hasOutcome('BRAND_NEW_STATUS'), isFalse);
      expect(ImportJobStatusValue.isInFlight('BRAND_NEW_STATUS'), isFalse);
    });
  });
}

