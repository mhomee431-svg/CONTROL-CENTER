import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/ui/numeric_input.dart';

/// Keyboard-level numeric guards must stop exactly the input the backend
/// rejects — and nothing else.
///
/// Backend authority: quantities are `ge=0, le=999_999`
/// (`ShopkeeperProductCreate` / the inventory update schemas), prices and MRPs
/// are `ge=0`, barcodes are the EAN-8 / UPC-A / EAN-13 / GTIN-14 digit
/// families, and stock deltas are signed integers. These tests pin the
/// client-side formatters to that contract, including the *intermediate*
/// states (`''`, `'-'`, `'12.'`) a shopkeeper inevitably types on the way to a
/// complete value — blocking those would make the field unusable.
void main() {
  /// Runs [text] through the formatter chain the way a real edit does — each
  /// formatter sees the result of the previous one — returning the text the
  /// field would end up holding.
  String applyAll(List<TextInputFormatter> formatters, String text) {
    var value = TextEditingValue.empty;
    var current = text;
    for (final formatter in formatters) {
      value = formatter.formatEditUpdate(
        value,
        TextEditingValue(
          text: current,
          selection: TextSelection.collapsed(offset: current.length),
        ),
      );
      current = value.text;
    }
    return current;
  }

  group('NumericInput.decimal (money, %, distance)', () {
    test('keeps digits and up to two fraction digits', () {
      expect(applyAll(NumericInput.decimal(), '1234.56'), '1234.56');
    });

    test('drops letters, currency symbols and group separators', () {
      expect(applyAll(NumericInput.decimal(), '12a3'), '123');
      expect(applyAll(NumericInput.decimal(), '₹12'), '12');
      expect(applyAll(NumericInput.decimal(), '1,234'), '1234');
      expect(applyAll(NumericInput.decimal(), '12.5.6'), '12.56');
    });

    test('stops at two fraction digits by default', () {
      expect(applyAll(NumericInput.decimal(), '12.345'), '12.34');
    });

    test('honours a custom fraction precision', () {
      expect(
          applyAll(NumericInput.decimal(decimals: 4), '12.34567'), '12.3456');
    });

    test('leaves the intermediate states a field must allow', () {
      expect(applyAll(NumericInput.decimal(), ''), '');
      expect(applyAll(NumericInput.decimal(), '12.'), '12.');
      expect(applyAll(NumericInput.decimal(), '.5'), '.5');
    });

    test('caps the integer part so a stuck keypad cannot overflow the API', () {
      expect(
        applyAll(NumericInput.decimal(), '1234567890123.45'),
        '123456789.45',
      );
    });

    test('rejects a sign by default', () {
      expect(applyAll(NumericInput.decimal(), '-5'), '5');
    });

    test('allowSign lets a field explain a negative amount', () {
      // The product form's validator says "Price cannot be negative" — the
      // field must be able to hold the value that triggers that message.
      expect(applyAll(NumericInput.decimal(allowSign: true), '-5'), '-5');
      expect(applyAll(NumericInput.decimal(allowSign: true), '1-5'), '15');
    });
  });

  group('NumericInput.whole (quantities, pincodes)', () {
    test('is digits only', () {
      expect(applyAll(NumericInput.whole(), '12a3'), '123');
      expect(applyAll(NumericInput.whole(), '-5'), '5');
      expect(applyAll(NumericInput.whole(), '1e3'), '13');
    });

    test('caps at six digits — the backend le=999_999 ceiling', () {
      expect(applyAll(NumericInput.whole(), '1234567'), '123456');
      expect(applyAll(NumericInput.whole(), '999999'), '999999');
    });

    test('honours a shorter cap (pincode, batch size)', () {
      expect(applyAll(NumericInput.whole(maxLength: 6), '8510017'), '851001');
      expect(applyAll(NumericInput.whole(maxLength: 5), '123456'), '12345');
    });
  });

  group('NumericInput.signedWhole (stock deltas)', () {
    test('keeps a leading minus', () {
      expect(applyAll(NumericInput.signedWhole(), '-25'), '-25');
      expect(applyAll(NumericInput.signedWhole(), '24'), '24');
    });

    test('allows the bare minus as an intermediate state', () {
      expect(applyAll(NumericInput.signedWhole(), '-'), '-');
    });

    test('rejects a minus anywhere but the leading position', () {
      expect(applyAll(NumericInput.signedWhole(), '2-5'), '25');
      // Only the first minus survives, so '--5' still means "minus five".
      expect(applyAll(NumericInput.signedWhole(), '--5'), '-5');
    });

    test('caps the digit count', () {
      expect(applyAll(NumericInput.signedWhole(), '-1234567'), '-123456');
    });
  });

  group('NumericInput.signedDecimal (manual lat/long)', () {
    test('keeps a signed decimal', () {
      expect(applyAll(NumericInput.signedDecimal(), '28.6139'), '28.6139');
      expect(applyAll(NumericInput.signedDecimal(), '-77.209'), '-77.209');
    });

    test('stops at six fraction digits', () {
      expect(
          applyAll(NumericInput.signedDecimal(), '28.6139123'), '28.613912');
    });

    test('drops letters', () {
      expect(applyAll(NumericInput.signedDecimal(), 'lat28.6'), '28.6');
    });
  });

  group('NumericInput.phone (stored contact numbers)', () {
    test('keeps the separators an already-stored number uses', () {
      expect(applyAll(NumericInput.phone(), '+91 98765 43210'),
          '+91 98765 43210');
    });

    test('blocks letters', () {
      expect(applyAll(NumericInput.phone(), '+91abc9876'), '+919876');
    });

    test('caps the overall length', () {
      expect(applyAll(NumericInput.phone(maxLength: 18), '1' * 25).length, 18);
    });
  });

  group('NumericInput.barcode (manual entry)', () {
    test('strips the separators printed on the pack', () {
      expect(
          applyAll(NumericInput.barcode(), '8 901234 567890'), '8901234567890');
      expect(
          applyAll(NumericInput.barcode(), '890-1234-5678-90'), '8901234567890');
    });

    test('keeps the digits of every retail length intact', () {
      for (final code in [
        '12345678',
        '123456789012',
        '1234567890123',
        '12345678901234',
      ]) {
        expect(applyAll(NumericInput.barcode(), code), code);
      }
    });

    test('leaves a letter for the validator to complain about', () {
      // Stripping the "O" here would look up a different, valid-looking code —
      // the field must keep the typo so the shopkeeper is told about it.
      expect(
          applyAll(NumericInput.barcode(), '89O1234567890'), '89O1234567890');
    });

    test('caps the field so a huge paste cannot balloon the input', () {
      expect(applyAll(NumericInput.barcode(), '1' * 30).length, 20);
    });
  });

  group('NumericInput returns fresh, independent lists', () {
    test('no state is shared between fields', () {
      final first = NumericInput.decimal();
      final second = NumericInput.decimal();
      expect(identical(first, second), isFalse);
      first.clear();
      expect(second.length, 1);
      expect(NumericInput.decimal().length, 1);
    });
  });
group('the guards are wired into a real field', () {
    Future<void> pumpField(
      WidgetTester tester,
      TextEditingController controller,
      List<TextInputFormatter> formatters,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: formatters,
            ),
          ),
        ),
      );
    }

    testWidgets('a price field rejects what the API would reject',
        (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpField(tester, controller, NumericInput.decimal());

      await tester.enterText(find.byType(TextField), '12abc.345');
      expect(controller.text, '12.34');
      // The value the sheet would send now parses cleanly.
      expect(double.tryParse(controller.text), 12.34);
    });

    testWidgets('a quantity field cannot exceed the backend ceiling',
        (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpField(tester, controller, NumericInput.whole());

      await tester.enterText(find.byType(TextField), '1000000');
      expect(controller.text, '100000');
      expect(int.parse(controller.text), lessThanOrEqualTo(999999));
    });

    testWidgets('a stock-delta field keeps the sign the shopkeeper typed',
        (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpField(tester, controller, NumericInput.signedWhole());

      await tester.enterText(find.byType(TextField), '-3');
      expect(controller.text, '-3');
      expect(int.tryParse(controller.text), -3);
    });
  });
}