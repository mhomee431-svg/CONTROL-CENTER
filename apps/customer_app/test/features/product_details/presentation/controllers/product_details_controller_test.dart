import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:hyperlocal_app/features/product_details/domain/product_details_repository.dart';
import 'package:hyperlocal_app/features/product_details/domain/models/product_details_models.dart';
import 'package:hyperlocal_app/features/product_details/presentation/controllers/product_details_controller.dart';
import 'package:hyperlocal_app/features/product_details/presentation/providers/product_details_providers.dart';

import 'product_details_controller_test.mocks.dart';

@GenerateMocks([ProductDetailsRepository])
void main() {
  group('ProductDetailsController', () {
    late MockProductDetailsRepository mockProductDetailsRepository;
    late ProviderContainer container;

    const productId = 'test_product_id';
    const productDetails = ProductDetails(
      product: ProductMasterDetails(
        id: productId,
        name: 'Test Product',
        brand: 'Test Brand',
        category: 'Test Category',
        description: 'Test Description',
        imageUrls: [],
        priceRange: '10-20',
      ),
      shopOffers: [],
    );

    setUp(() {
      mockProductDetailsRepository = MockProductDetailsRepository();
      container = ProviderContainer(
        overrides: [
          productDetailsRepositoryProvider.overrideWithValue(
            mockProductDetailsRepository,
          ),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('productDetailsProvider success', () async {
      when(mockProductDetailsRepository.getProductDetails(productId))
          .thenAnswer((_) async => productDetails);

      final result = await container.read(
        productDetailsProvider(productId).future,
      );

      expect(result, productDetails);
      verify(mockProductDetailsRepository.getProductDetails(productId));
      verifyNoMoreInteractions(mockProductDetailsRepository);
    });

        test('productDetailsProvider error', () async {
      final exception = Exception('Failed to fetch');
      when(mockProductDetailsRepository.getProductDetails(productId))
          .thenThrow(exception);

      final provider = productDetailsProvider(productId);

      // container.listen keeps the autoDispose provider alive and observes
      // state transitions. The mock throws on getProductDetails, so Riverpod
      // first enters AsyncLoading-with-error, then transitions to AsyncError.
      final completer = Completer<void>();
      final sub = container.listen(provider, (previous, next) {
        if (next.hasError && identical(next.error, exception)) {
          completer.complete();
        }
      });

      // Trigger evaluation
      container.read(provider);

      // Wait for the error state to be observed.
      await completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => fail('Timed out waiting for error state'),
      );

      // Provider should now be in an error state (kept alive by listener).
      final result = container.read(provider);
      expect(result.hasError, isTrue);
      expect(result.error, same(exception));

      verify(mockProductDetailsRepository.getProductDetails(productId));
      verifyNoMoreInteractions(mockProductDetailsRepository);

      sub.close();
    });

    test('toggleSave calls repository', () async {
      when(mockProductDetailsRepository.toggleSaveProduct(productId, true))
          .thenAnswer((_) async => {});

      await container
          .read(productActionControllerProvider.notifier)
          .toggleSave(productId, false);

      verify(mockProductDetailsRepository.toggleSaveProduct(productId, true));
      verifyNoMoreInteractions(mockProductDetailsRepository);

      when(mockProductDetailsRepository.toggleSaveProduct(productId, false))
          .thenAnswer((_) async => {});

      await container
          .read(productActionControllerProvider.notifier)
          .toggleSave(productId, true);

      verify(mockProductDetailsRepository.toggleSaveProduct(productId, false));
      verifyNoMoreInteractions(mockProductDetailsRepository);
    });
  });
}
