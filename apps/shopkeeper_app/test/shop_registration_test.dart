import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/data/shop_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/domain/shop_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/shop_registration/data/document_picker_service.dart';
import 'package:hyperlocal_shopkeeper_app/features/shop_registration/domain/shop_registration_state.dart';
import 'package:hyperlocal_shopkeeper_app/features/shop_registration/controllers/shop_registration_controller.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer makeContainer(FakeShopRepo shopRepo) => ProviderContainer(
        overrides: [
          tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token'),
          ),
          shopRepositoryProvider.overrideWithValue(shopRepo),
          documentPickerProvider.overrideWithValue(_FakePicker()),
        ],
      );

  group('ShopRegistrationController', () {
    test('loads categories on build', () async {
      final shopRepo = FakeShopRepo();
      final container = makeContainer(shopRepo)
        ..read(shopRegistrationControllerProvider);
      // allow the microtask loadCategories to run
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final state = container.read(shopRegistrationControllerProvider);
      expect(state.categories, isNotEmpty);
      expect(state.categories.first.code, 'PHARMACY_HEALTHCARE');
      expect(state.categoriesLoading, isFalse);
    });

    test('selecting a category loads requirements and builds slots',
        () async {
      final shopRepo = FakeShopRepo();
      final container = makeContainer(shopRepo)
        ..read(shopRegistrationControllerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final notifier =
          container.read(shopRegistrationControllerProvider.notifier);
      final initialState = container.read(shopRegistrationControllerProvider);
      await notifier.selectCategory(initialState.categories.first);

      final state = container.read(shopRegistrationControllerProvider);
      expect(state.category, isNotNull);
      expect(state.requirements, isNotNull);
      // Universal documents become slots.
      expect(state.slots.containsKey('GST_CERTIFICATE'), isTrue);
      expect(state.slots.containsKey('SHOP_PHOTO'), isTrue);
    });

    test('validators reject invalid GSTIN/Udyam but allow empty', () {
      expect(ShopRegistrationValidators.gstin(''), isNull);
      expect(ShopRegistrationValidators.gstin('22AAAAA0000A1Z5'), isNull);
      expect(ShopRegistrationValidators.gstin('not-a-gstin'), isNotNull);
      expect(ShopRegistrationValidators.udyam(''), isNull);
      expect(ShopRegistrationValidators.udyam('UDYAM-DL-0000123456'), isNull);
      expect(ShopRegistrationValidators.udyam('bad'), isNotNull);
      expect(ShopRegistrationValidators.pincode('851001'), isNull);
      expect(ShopRegistrationValidators.pincode('000000'), isNotNull);
      expect(ShopRegistrationValidators.pincode('12345'), isNotNull);
    });

    test('nextFromBusinessInfo validates required fields', () async {
      final shopRepo = FakeShopRepo();
      final container = makeContainer(shopRepo)
        ..read(shopRegistrationControllerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final notifier =
          container.read(shopRegistrationControllerProvider.notifier);

      // Start on the business-information step.
      notifier.startBusinessInfo();
      expect(
          container.read(shopRegistrationControllerProvider).step,
          RegistrationStep.businessInfo);

      // Empty form → error, step stays.
      final err = notifier.nextFromBusinessInfo();
      expect(err, isNotNull);
      expect(
          container.read(shopRegistrationControllerProvider).step,
          RegistrationStep.businessInfo);

      // Fill required fields.
      notifier.setShopName('Sharma Medical Store');
      await notifier.selectCategory(
          container.read(shopRegistrationControllerProvider).categories.first);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      notifier.setBusinessType('Retail');

      final err2 = notifier.nextFromBusinessInfo();
      expect(err2, isNull);
      expect(container.read(shopRegistrationControllerProvider).step,
          RegistrationStep.location);
    });

    test('submit blocks without a location pin', () async {
      final shopRepo = FakeShopRepo();
      final container = makeContainer(shopRepo)
        ..read(shopRegistrationControllerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final notifier =
          container.read(shopRegistrationControllerProvider.notifier);
      final result = await notifier.submit();
      expect(result, isNull);
      expect(
          container.read(shopRegistrationControllerProvider).submitError,
          isNotNull);
    });
  });
}

/// Deterministic picker that returns a tiny in-memory "file" for tests.
class _FakePicker implements DocumentPickerService {
  @override
  Future<PickedFile?> pick({
    required PickSource source,
    required DocumentMediaCategory mediaCategory,
  }) async {
    return PickedFile(
      path: '/tmp/test_file.pdf',
      name: 'test_file.pdf',
      sizeBytes: 1024,
      mimeType: 'application/pdf',
    );
  }
}
