import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hyperlocal_shopkeeper_app/features/shop_registration/domain/shop_registration_state.dart';
import 'package:hyperlocal_shopkeeper_app/features/shop_registration/presentation/widgets/shop_location_details.dart';

void main() {
  Future<void> showDetails(
    WidgetTester tester,
    ShopRegistrationState state, {
    ValueChanged<LatLng>? onAdjust,
    VoidCallback? onConfirmDrift,
  }) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ShopLocationDetails(
                state: state,
                onAdjust: onAdjust ?? (_) {},
                onConfirmDrift: onConfirmDrift ?? () {},
              ),
            ),
          ),
        ),
      );

  testWidgets('shows capture, found, failure and permission states', (
    tester,
  ) async {
    for (final entry in {
      RegistrationLocationStatus.locating: 'Getting location...',
      RegistrationLocationStatus.ready: 'Location found',
      RegistrationLocationStatus.error: 'Unable to get location',
      RegistrationLocationStatus.serviceDisabled: 'Unable to get location',
      RegistrationLocationStatus.permissionDenied: 'Permission denied',
    }.entries) {
      await showDetails(
        tester,
        ShopRegistrationState(locationStatus: entry.key),
      );
      expect(find.text(entry.value), findsOneWidget);
    }
  });

  testWidgets('manual correction validates before applying coordinates', (
    tester,
  ) async {
    LatLng? result;
    await showDetails(
      tester,
      const ShopRegistrationState(),
      onAdjust: (pin) => result = pin,
    );
    final fields = find.byType(TextFormField);
    for (final invalid in ['91', 'NaN', 'Infinity', 'invalid']) {
      await tester.enterText(fields.at(0), invalid);
      await tester.enterText(fields.at(1), '181');
      await tester.tap(find.text('Apply manual correction'));
      await tester.pump();
      expect(result, isNull);
      expect(find.textContaining('Enter a number'), findsNWidgets(2));
    }
    await tester.enterText(fields.at(0), '-25.123456');
    await tester.enterText(fields.at(1), '85.654321');
    await tester.tap(find.text('Apply manual correction'));
    await tester.pump();
    expect(result, const LatLng(-25.123456, 85.654321));
  });

  testWidgets('GPS and map updates refresh coordinate fields', (tester) async {
    await showDetails(tester, const ShopRegistrationState(pin: LatLng(10, 20)));
    expect(find.text('10.000000'), findsOneWidget);
    await showDetails(tester, const ShopRegistrationState(pin: LatLng(11, 21)));
    expect(find.text('11.000000'), findsOneWidget);
    expect(find.text('21.000000'), findsOneWidget);
  });

  testWidgets('adjusted pin never inherits GPS accuracy estimate', (
    tester,
  ) async {
    await showDetails(
      tester,
      const ShopRegistrationState(
        pin: LatLng(10, 20),
        pinAdjusted: true,
        accuracyMeters: 7,
        locationStatus: RegistrationLocationStatus.ready,
      ),
    );
    expect(
      find.text('Location accuracy: unknown for the adjusted pin'),
      findsOneWidget,
    );
    expect(find.textContaining('Accuracy: 7 m'), findsNothing);
    expect(find.textContaining('estimate, not a guarantee'), findsOneWidget);
  });

  testWidgets('manual correction is disabled during GPS acquisition', (
    tester,
  ) async {
    await showDetails(
      tester,
      const ShopRegistrationState(
        locationStatus: RegistrationLocationStatus.locating,
      ),
    );
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
    for (final field in tester.widgetList<TextFormField>(
      find.byType(TextFormField),
    )) {
      expect(field.enabled, isFalse);
    }
  });

  testWidgets('far-moved pin asks for confirmation before continuing', (
    tester,
  ) async {
    var confirmed = false;
    await showDetails(
      tester,
      const ShopRegistrationState(
        pin: LatLng(10, 20),
        pinAdjusted: true,
        pinDriftMeters: 1200,
        locationStatus: RegistrationLocationStatus.ready,
      ),
      onConfirmDrift: () => confirmed = true,
    );
    expect(find.textContaining('about 1200 m away'), findsOneWidget);
    expect(find.textContaining('Are you sure'), findsOneWidget);
    await tester.tap(find.text('Yes, this is my shop entrance'));
    await tester.pump();
    expect(confirmed, isTrue);
  });

  testWidgets('no confirmation prompt within the drift threshold', (
    tester,
  ) async {
    await showDetails(
      tester,
      const ShopRegistrationState(
        pin: LatLng(10, 20),
        pinAdjusted: true,
        pinDriftMeters: 20,
        locationStatus: RegistrationLocationStatus.ready,
      ),
    );
    expect(find.textContaining('Are you sure'), findsNothing);

    // Already-confirmed drift never re-prompts.
    await showDetails(
      tester,
      const ShopRegistrationState(
        pin: LatLng(10, 20),
        pinAdjusted: true,
        pinDriftMeters: 1200,
        pinDriftConfirmed: true,
        locationStatus: RegistrationLocationStatus.ready,
      ),
    );
    expect(find.textContaining('Are you sure'), findsNothing);
  });
}
