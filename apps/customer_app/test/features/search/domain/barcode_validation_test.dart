import 'package:flutter_test/flutter_test.dart';

import 'package:hyperlocal_app/features/search/domain/barcode_validation.dart';

void main() {
  group('normalizeBarcode', () {
    test('strips spaces, dashes and surrounding whitespace', () {
      expect(normalizeBarcode(' 890-1234 567890 '), '8901234567890');
      expect(normalizeBarcode(null), isEmpty);
      expect(normalizeBarcode(''), isEmpty);
    });
  });

  group('validateBarcode', () {
    test('accepts real GS1 codes (EAN-8/UPC-A/EAN-13/GTIN-14)', () {
      // Same vectors as the backend's `validate_barcode_format` tests.
      expect(validateBarcode('96385074'), isNull); // EAN-8
      expect(validateBarcode('036000291452'), isNull); // UPC-A
      expect(validateBarcode('8901234567890'), isNull); // EAN-13
      expect(validateBarcode('12345678901231'), isNull); // GTIN-14
    });

    test('rejects empty input without a network call', () {
      expect(validateBarcode(null), BarcodeInvalidReason.empty);
      expect(validateBarcode('   '), BarcodeInvalidReason.empty);
    });

    test('rejects characters no retail symbology uses', () {
      // A GS1 code is digits-only, and the deliberately-permissive Code128 path
      // allows alphanumerics — so only non-alphanumeric noise is "non-numeric".
      expect(validateBarcode('89#4567890'), BarcodeInvalidReason.nonNumeric);
      expect(validateBarcode('89 45*67'), BarcodeInvalidReason.nonNumeric);
      expect(validateBarcode('A1'), BarcodeInvalidReason.nonNumeric);
    });

    test('rejects wrong lengths', () {
      expect(validateBarcode('12345'), BarcodeInvalidReason.invalidLength);
      expect(
        validateBarcode('12345678901234567890'),
        BarcodeInvalidReason.invalidLength,
      );
    });

    test('rejects a bad GS1 check digit (the classic partial/angled read)', () {
      // Same vector as the backend's `bad_check_digit` test: flipping the last
      // digit of the known-good demo code must fail.
      expect(
        validateBarcode('8901234567891'),
        BarcodeInvalidReason.badCheckDigit,
      );
    });

    test('accepts plausible Code128 reads (no check digit exists)', () {
      // Weighted goods / inner packs print alphanumeric codes the GS1 rules do
      // not cover; rejecting them would break real shelf labels.
      expect(validateBarcode('AB12CD34'), isNull);
      expect(validateBarcode('A1'), BarcodeInvalidReason.nonNumeric);
    });

    test('every reason has customer-readable copy', () {
      for (final reason in BarcodeInvalidReason.values) {
        final message = invalidBarcodeMessage(reason);
        expect(message, isNotEmpty);
        // Copy must never leak rule names or regexes.
        expect(message, isNot(contains('RegExp')));
        expect(message, isNot(contains('GS1')));
      }
    });
  });
}
