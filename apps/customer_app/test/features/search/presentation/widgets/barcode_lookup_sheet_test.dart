import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyperlocal_app/features/search/data/mock_search_repository.dart';
import 'package:hyperlocal_app/features/search/domain/search_repository.dart';
import 'package:hyperlocal_app/features/search/presentation/widgets/barcode_lookup_sheet.dart';

Widget _wrap(Widget child, SearchRepository repo) {
  return ProviderScope(
    overrides: [searchRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  testWidgets(
    'barcode sheet prompts for input and shows no result before submit',
    (tester) async {
      await tester.pumpWidget(
        _wrap(const BarcodeLookupSheet(), MockSearchRepository()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Scan barcode'), findsOneWidget);
      expect(find.byKey(const Key('barcodeInput')), findsOneWidget);
      // No lookup has been made yet, so no results are claimed.
      expect(find.text('No match found'), findsNothing);
    },
  );

  testWidgets('a known barcode lists the real shops selling it', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const BarcodeLookupSheet(), MockSearchRepository()),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('barcodeInput')),
      '8901234567890',
    );
    await tester.tap(find.byKey(const Key('barcodeSubmit')));
    await tester.pumpAndSettle();

    expect(find.text('Gupta Electronics'), findsOneWidget);
    expect(find.text('Bosch Impact Drill 13mm'), findsOneWidget);
    expect(find.text('No match found'), findsNothing);
  });

  testWidgets(
    'an unknown barcode reports not found instead of inventing a product',
    (tester) async {
      await tester.pumpWidget(
        _wrap(const BarcodeLookupSheet(), MockSearchRepository()),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('barcodeInput')),
        '0000000000000',
      );
      await tester.tap(find.byKey(const Key('barcodeSubmit')));
      await tester.pumpAndSettle();

      expect(find.text('No match found'), findsOneWidget);
      expect(find.text('Gupta Electronics'), findsNothing);
    },
  );

  test(
    'lookupBarcode trims input and returns nothing for a blank barcode',
    () async {
      final repo = MockSearchRepository();
      // Blank barcodes never reach the network.
      expect(await repo.lookupBarcode('   '), isEmpty);
    },
  );
}
