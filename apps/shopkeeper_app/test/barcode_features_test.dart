import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/barcode/data/barcode_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/barcode/domain/barcode_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/barcode/presentation/controllers/barcode_controller.dart';

import 'fakes.dart';

void main() {
  ProviderContainer makeContainer({required BarcodeRepository repo}) {
    final container = ProviderContainer(overrides: [
      barcodeRepositoryProvider.overrideWithValue(repo),
      tokenStoreProvider.overrideWithValue(
          InMemoryTokenStore(accessToken: 'test-access-token')),
      selectedShopProvider
          .overrideWith(() => SelectedShopOverride(ownerShop(id: 10))),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  group('BarcodeController', () {
    test('resolves a FOUND barcode to catalog matches', () async {
      final fake = FakeBarcodeRepo(onResolve: foundResolution());
      final container = makeContainer(repo: fake);

      await container.read(barcodeControllerProvider.notifier).resolve('8901234567890');

      final state = container.read(barcodeControllerProvider);
      expect(state.status, BarcodeScanStatus.resolved);
      expect(state.scannedBarcode, '8901234567890');
      expect(state.resolution, isNotNull);
      expect(state.resolution!.status, BarcodeResolutionStatus.found);
      expect(state.resolution!.matches, hasLength(1));
      expect(state.resolution!.matches.first.name, contains('Aashirvaad'));
      expect(fake.lastBarcode, '8901234567890');
      expect(fake.lastShopId, 10);
    });

    test('resolves a MULTIPLE_MATCHES result without throwing', () async {
      const multiple = BarcodeResolution(
        status: BarcodeResolutionStatus.multipleMatches,
        barcode: '8901234567890',
        message: '2 catalog products share this barcode',
        matches: [
          CatalogProductMatch(
            productMasterId: 1,
            name: 'Product A',
            isAvailableInCatalog: true,
            matchType: 'IDENTIFIER',
          ),
          CatalogProductMatch(
            productMasterId: 2,
            name: 'Product B',
            isAvailableInCatalog: true,
            matchType: 'ALTERNATE',
          ),
        ],
      );
      final fake = FakeBarcodeRepo(onResolve: multiple);
      final container = makeContainer(repo: fake);

      await container.read(barcodeControllerProvider.notifier).resolve('8901234567890');

      final state = container.read(barcodeControllerProvider);
      expect(state.status, BarcodeScanStatus.resolved);
      expect(state.resolution!.status, BarcodeResolutionStatus.multipleMatches);
      expect(state.resolution!.matches, hasLength(2));
    });

    test('resolves a NOT_FOUND barcode without throwing', () async {
      final fake = FakeBarcodeRepo(
        onResolve: const BarcodeResolution(
          status: BarcodeResolutionStatus.notFound,
          barcode: '999999999999',
        ),
      );
      final container = makeContainer(repo: fake);

      await container.read(barcodeControllerProvider.notifier).resolve('999999999999');

      final state = container.read(barcodeControllerProvider);
      expect(state.status, BarcodeScanStatus.resolved);
      expect(state.resolution!.status, BarcodeResolutionStatus.notFound);
      expect(state.resolution!.matches, isEmpty);
    });

    test('maps a network failure to an error state with friendly copy', () async {
      final fake = FakeBarcodeRepo(
        error: const ApiException(statusCode: null, message: 'Network error'),
      );
      final container = makeContainer(repo: fake);

      await container.read(barcodeControllerProvider.notifier).resolve('8901234567890');

      final state = container.read(barcodeControllerProvider);
      expect(state.status, BarcodeScanStatus.error);
      expect(state.message, isNotNull);
      expect(state.message, contains('internet'));
    });

    test('saveFromScan persists the confirmed payload to inventory', () async {
      final fake = FakeBarcodeRepo();
      final container = makeContainer(repo: fake);

      final item = await container
          .read(barcodeControllerProvider.notifier)
          .saveFromScan(BarcodeSavePayload(
            barcode: '8901234567890',
            productMasterId: 101,
            price: 85,
            mrp: 95,
            quantity: 10,
            publish: true,
          ));

      expect(item, isNotNull);
      expect(item!.price, 85);
      expect(item.quantity, 10);
      expect(fake.lastPayload, isNotNull);
      expect(fake.lastPayload!.productMasterId, 101);
      // State returns to idle after a successful save.
      expect(container.read(barcodeControllerProvider).status,
          BarcodeScanStatus.idle);
    });
  });
}