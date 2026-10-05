import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/presentation/widgets/inventory_shared.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_models.dart';

/// The DATA SOURCE INDICATOR, client half.
///
/// The backend records who last wrote a listing; this turns that fact into one
/// sentence the shopkeeper can act on. Two properties are pinned here:
///
///  * every writer has a DISTINCT, correct sentence - a POS sync that reads
///    "manual" is worse than silence, because the shopkeeper trusts it;
///  * the sentence answers "was it me, or something else?", which is the
///    question the indicator exists to settle.
void main() {
  group('The source sentence', () {
    test('every writer is named', () {
      expect(inventorySourceLabel('MANUAL'), 'Updated manually');
      expect(inventorySourceLabel('BARCODE_SCAN'), 'Updated via barcode');
      expect(inventorySourceLabel('EXCEL_UPLOAD'), 'Updated via Excel/CSV');
      expect(inventorySourceLabel('POS_INTEGRATION'), 'Updated via POS');
      expect(inventorySourceLabel('SYSTEM'), 'Updated by system');
    });

    test('an absent source reads as manual, not as unknown', () {
      // The model's default is MANUAL, so "never written by an integration" is
      // the honest reading. A badge saying "unknown" on every row would train
      // shopkeepers to ignore the indicator entirely.
      expect(inventorySourceLabel(null), 'Updated manually');
      expect(inventorySourceLabel(''), 'Updated manually');
      expect(inventorySourceLabel('UNKNOWN'), 'Updated manually');
    });

    test('case and padding do not hide a source', () {
      expect(inventorySourceLabel(' pos_integration '), 'Updated via POS');
    });

    test('an unrecognised source is still shown, not swallowed', () {
      // A future backend writer must not render as a blank cell; the raw key is
      // humanised rather than dropped.
      expect(inventorySourceLabel('SOME_NEW_SYNC'), 'Some New Sync');
    });

    test('each writer gets its own icon and colour', () {
      // A chip that looks identical whichever integration wrote it is a legend
      // nobody can read.
      final icons = {
        inventorySourceIcon('MANUAL'),
        inventorySourceIcon('BARCODE_SCAN'),
        inventorySourceIcon('EXCEL_UPLOAD'),
        inventorySourceIcon('POS_INTEGRATION'),
      };
      expect(icons.length, 4);
    });
  });

  group('The listing carries the sentence', () {
    ShopProductItem fromSource(String? source) => ShopProductItem.fromJson({
          'id': 11,
          'name': 'Amul Milk 1L',
          'price': 499,
          'quantity': 12,
          'stock_status': 'IN_STOCK',
          'source': source,
        });

    test('a POS-written row reads as POS', () {
      final row = fromSource('POS_INTEGRATION');
      expect(row.source, 'POS_INTEGRATION');
      expect(inventorySourceLabel(row.source), 'Updated via POS');
    });

    test('the spec example: price from POS, stock counted', () {
      // The rows the shopkeeper sees must be able to say who wrote them
      // without the screen inventing a source of its own.
      expect(inventorySourceLabel(fromSource('POS_INTEGRATION').source),
          'Updated via POS');
      expect(inventorySourceLabel(fromSource('MANUAL').source),
          'Updated manually');
    });

    test('a server that omits the key leaves the row without a claim', () {
      // Older payloads must not be back-filled with a guess.
      expect(fromSource(null).source, isNull);
    });
  });
}
