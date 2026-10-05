import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/validation/field_rules.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_form_rules.dart';

/// UI-level data validation for the surfaces `ProductFormRules` does not cover.
///
/// The app already owns price / MRP / quantity / product-name rules in
/// `ProductFormRules`, which returns CODES and resolves through the l10n layer.
/// Restating them here would be the exact drift this spec warns about, so this
/// file tests only the import, file, stock-adjustment and date rules, plus one
/// test proving the two limit sets still agree with each other.
void main() {
  group('Field limits', () {
    test('the defaults match FIELD_LIMITS in the backend', () {
      // Read the backend table rather than restating it, so a change on either
      // side surfaces here instead of in production.
      final source = _backendFieldLimits();
      if (source == null) {
        markTestSkipped('backend/app/core/field_limits.py not reachable');
        return;
      }
      for (final entry in source.entries) {
        expect(
          FieldLimits.defaults.of(entry.key),
          entry.value,
          reason: '${entry.key} limit drifted between client and server',
        );
      }
    });

    test('the import limits agree with the product-form limits', () {
      // Both mirror the same database columns: a name the manual form accepts
      // must not be rejected by the importer, or vice versa.
      expect(
        FieldLimits.defaults.of(FieldLimits.productName),
        ProductFormRules.nameMaxLength,
      );
      expect(
        FieldLimits.defaults.of(FieldLimits.brand),
        ProductFormRules.brandMaxLength,
      );
      expect(
        FieldLimits.defaults.of(FieldLimits.sku),
        ProductFormRules.skuMaxLength,
      );
      expect(
        FieldLimits.defaults.of(FieldLimits.barcode),
        ProductFormRules.barcodeMaxLength,
      );
    });

    test('the server schema replaces the defaults when it arrives', () {
      final limits = FieldLimits.fromSchema({'product_name': 80, 'brand': 10});
      expect(limits.of(FieldLimits.productName), 80);
      expect(limits.of(FieldLimits.brand), 10);
      // A field the server did not mention keeps the built-in default, so a
      // newer server cannot leave the client with no limit at all.
      expect(limits.of(FieldLimits.sku), 100);
    });

    test('a nonsense server limit is ignored rather than adopted', () {
      final limits = FieldLimits.fromSchema({'product_name': 0, 'sku': -5});
      expect(limits.of(FieldLimits.productName), 255);
      expect(limits.of(FieldLimits.sku), 100);
    });

    test('no schema at all leaves the built-in limits in place', () {
      expect(identical(FieldLimits.fromSchema(null), FieldLimits.defaults), isTrue);
    });

    test('a value at the limit is accepted', () {
      expect(importFieldTooLong('x' * 255, FieldLimits.productName), isNull);
    });

    test('one character over is rejected with the numbers to act on', () {
      final message = importFieldTooLong('x' * 256, FieldLimits.productName)!;
      expect(message, contains('256'));
      expect(message, contains('255'));
    });

    test('surrounding whitespace does not count', () {
      expect(importFieldTooLong('  ${'x' * 255}  ', FieldLimits.productName), isNull);
    });

    test('an absent field is not too long', () {
      expect(importFieldTooLong(null, FieldLimits.brand), isNull);
      expect(importFieldTooLong('', FieldLimits.brand), isNull);
    });

    test('each field has its own limit', () {
      // 101 characters fits a name but not a SKU.
      final text = 'x' * 101;
      expect(importFieldTooLong(text, FieldLimits.productName), isNull);
      expect(importFieldTooLong(text, FieldLimits.sku), isNotNull);
    });
  });

  group('Stock adjustment', () {
    test('a negative adjustment is allowed', () {
      // Removing stock is the whole point of a negative delta.
      expect(stockDelta('-3'), isNull);
      expect(stockDelta('5'), isNull);
    });

    test('zero is not a change', () {
      expect(stockDelta('0'), 'Enter a non-zero quantity change');
    });

    test('a fractional adjustment is rejected', () {
      expect(stockDelta('2.5'), 'Enter a whole number');
    });

    test('a blank adjustment asks for one', () {
      expect(stockDelta(''), 'Enter a quantity change');
      expect(stockDelta('  '), 'Enter a quantity change');
    });

    test('it is not the same rule as a product stock value', () {
      // ProductFormRules.quantity judges an absolute value (0 fine, negative
      // not). An adjustment is a signed delta where 0 is meaningless. Merging
      // them would make one of the two screens wrong.
      expect(ProductFormRules.quantity('0'), isNull);
      expect(ProductFormRules.quantity('-1'), isNotNull);
      expect(stockDelta('0'), isNotNull);
      expect(stockDelta('-1'), isNull);
    });
  });

  group('Offer dates', () {
    test('an offer must end after it starts', () {
      expect(
        offerDateRange(DateTime(2026, 11, 1), DateTime(2026, 10, 1)),
        'End date must be after the start date',
      );
    });

    test('ending the same day is not after', () {
      final same = DateTime(2026, 11, 1);
      expect(offerDateRange(same, same), isNotNull);
    });

    test('a forward-dated offer passes', () {
      expect(offerDateRange(DateTime(2026, 11, 1), DateTime(2026, 11, 10)), isNull);
    });

    test('a missing date asks for it', () {
      expect(offerDateRange(null, DateTime(2026, 11, 10)), 'Choose a start date');
      expect(offerDateRange(DateTime(2026, 11, 1), null), 'Choose an end date');
    });

    test('today is not in the past', () {
      // Compared by DAY: an offer starting today is valid whatever the hour.
      expect(
        notInThePast(
          DateTime(2026, 11, 1, 0, 5),
          'Start date',
          now: DateTime(2026, 11, 1, 23, 30),
        ),
        isNull,
      );
    });

    test('yesterday is in the past', () {
      expect(
        notInThePast(
          DateTime(2026, 10, 31),
          'Start date',
          now: DateTime(2026, 11, 1, 9),
        ),
        contains('past'),
      );
    });
  });

  group('Workbook selection', () {
    test('an .xlsx file is accepted', () {
      expect(importWorkbook('stock.xlsx'), isNull);
      expect(importWorkbook('STOCK.XLSX'), isNull);
    });

    test('another extension is refused before uploading', () {
      expect(importWorkbook('stock.csv'), contains('.xlsx'));
      expect(importWorkbook('photo.jpg'), isNotNull);
    });

    test('no file chosen yet says so', () {
      expect(importWorkbook('  '), 'Choose a workbook to upload');
    });

    test('an oversized file is refused with both sizes', () {
      final message = importWorkbook('big.xlsx', bytes: 8 * 1024 * 1024)!;
      expect(message, contains('8.0 MB'));
      expect(message, contains('maximum'));
    });

    test('a file at the cap is accepted', () {
      expect(importWorkbook('ok.xlsx', bytes: FieldLimits.maxFileBytes), isNull);
    });

    test('an unknown size is left to the server', () {
      // The picker does not always report a size; guessing is worse than
      // letting the backend be the authority.
      expect(importWorkbook('ok.xlsx', bytes: null), isNull);
    });
  });
}

/// The backend `FIELD_LIMITS` table, or null when it cannot be read (the app may
/// be tested outside the repository).
Map<String, int>? _backendFieldLimits() {
  // Tests run with CWD at the app package root, so `../..` is the repo root.
  final file = File('../../backend/app/core/field_limits.py');
  if (!file.existsSync()) return null;
  final source = file.readAsStringSync();
  final block =
      RegExp(r'FIELD_LIMITS[^=]*=\s*\{(.*?)\}', dotAll: true).firstMatch(source)?.group(1);
  if (block == null) return null;
  final out = <String, int>{};
  for (final m in RegExp(r'"([a-z_]+)":\s*(\d+)').allMatches(block)) {
    out[m.group(1)!] = int.parse(m.group(2)!);
  }
  return out.isEmpty ? null : out;
}
