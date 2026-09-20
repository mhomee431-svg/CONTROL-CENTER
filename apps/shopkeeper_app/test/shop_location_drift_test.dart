import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/data/location_accuracy_config.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/data/location_service.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/data/shop_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/domain/location_capture_state.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/presentation/controllers/location_capture_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/shop_registration/controllers/shop_registration_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/shop_registration/domain/shop_registration_state.dart';

import 'fakes.dart';

/// Capture controller pinned to a known GPS fix so drift is deterministic and
/// no platform location APIs are touched.
class _FixedFixCapture extends LocationCaptureController {
  @override
  LocationCaptureState build() => LocationCaptureState(
        status: LocationCaptureStatus.locationReady,
        deviceReading: GpsReading(
          latitude: 25.5941,
          longitude: 85.1376,
          timestamp: DateTime(2026, 9, 18, 12),
          accuracy: 7,
        ),
        shopPin: const LatLng(25.5941, 85.1376),
        accuracyMeters: 7,
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const deviceFix = LatLng(25.5941, 85.1376);
  // ~24 km away — well beyond the drift warning threshold.
  const farPin = LatLng(25.8, 85.35);

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        tokenStoreProvider.overrideWithValue(
          InMemoryTokenStore(accessToken: 'test-access-token'),
        ),
        shopRepositoryProvider.overrideWithValue(FakeShopRepo()),
        locationCaptureControllerProvider.overrideWith(_FixedFixCapture.new),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  void fillAddressFields(ShopRegistrationController notifier) {
    notifier.setAddressLine('Ghusiya Kala, Main Road');
    notifier.setCity('Bikramganj');
    notifier.setStateName('Bihar');
    notifier.setPincode('851001');
  }

  /// Walks the wizard from welcome to the location step so step transitions
  /// are asserted against the real pipeline.
  Future<void> advanceToLocation(
    ProviderContainer container,
    ShopRegistrationController notifier,
  ) async {
    notifier.startBusinessInfo();
    await notifier.selectCategory(
      container.read(shopRegistrationControllerProvider).categories.first,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    notifier.setBusinessType('Retail');
    notifier.setShopName('Sharma Medical Store');
    expect(notifier.nextFromBusinessInfo(), isNull);
    expect(
      container.read(shopRegistrationControllerProvider).step,
      RegistrationStep.location,
    );
  }

  test('pin at the GPS fix advances without a drift prompt', () async {
    final container = makeContainer()..read(shopRegistrationControllerProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final notifier = container.read(
      shopRegistrationControllerProvider.notifier,
    );
    fillAddressFields(notifier);

    notifier.movePin(deviceFix);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(shopRegistrationControllerProvider);
    expect(state.pinDriftMeters, lessThan(1));
    expect(state.needsPinDriftConfirmation, isFalse);
    expect(notifier.nextFromLocation(), isNull);
    expect(
      container.read(shopRegistrationControllerProvider).step,
      RegistrationStep.documents,
    );
  });

  test('far-moved pin blocks Next until the shopkeeper confirms', () async {
    final container = makeContainer()..read(shopRegistrationControllerProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final notifier = container.read(
      shopRegistrationControllerProvider.notifier,
    );
    await advanceToLocation(container, notifier);
    fillAddressFields(notifier);

    notifier.movePin(farPin);
    await Future<void>.delayed(Duration.zero);

    final adjusted = container.read(shopRegistrationControllerProvider);
    expect(
      adjusted.pinDriftMeters,
      greaterThan(LocationAccuracyConfig.pinDriftWarningMeters),
    );
    expect(adjusted.pinAdjusted, isTrue);
    expect(adjusted.needsPinDriftConfirmation, isTrue);

    // Guard: Next is refused and the wizard stays on the location step.
    expect(notifier.nextFromLocation(), isNotNull);
    expect(
      container.read(shopRegistrationControllerProvider).step,
      RegistrationStep.location,
    );

    notifier.confirmPinDrift();
    expect(
      container.read(shopRegistrationControllerProvider).pinDriftConfirmed,
      isTrue,
    );
    expect(notifier.needsDriftConfirmation, isFalse);

    expect(notifier.nextFromLocation(), isNull);
    expect(
      container.read(shopRegistrationControllerProvider).step,
      RegistrationStep.documents,
    );
  });

  test('a fresh GPS fix clears drift and the confirmation flag', () async {
    final container = makeContainer()..read(shopRegistrationControllerProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final notifier = container.read(
      shopRegistrationControllerProvider.notifier,
    );

    notifier.movePin(farPin);
    await Future<void>.delayed(Duration.zero);
    notifier.confirmPinDrift();
    expect(
      container.read(shopRegistrationControllerProvider).pinDriftConfirmed,
      isTrue,
    );

    notifier.movePin(deviceFix);
    await Future<void>.delayed(Duration.zero);
    final state = container.read(shopRegistrationControllerProvider);
    expect(state.pinDriftMeters, lessThan(1));
    expect(state.needsPinDriftConfirmation, isFalse);
  });
}
