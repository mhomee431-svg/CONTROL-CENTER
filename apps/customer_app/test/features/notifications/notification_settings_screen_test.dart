import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/storage/local_storage_driver.dart';
import 'package:hyperlocal_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:hyperlocal_app/features/notifications/data/mock_notification_repository.dart';
import 'package:hyperlocal_app/features/notifications/domain/models/notification_preferences.dart';
import 'package:hyperlocal_app/features/notifications/domain/notification_repository.dart';
import 'package:hyperlocal_app/features/notifications/presentation/controllers/notification_preferences_controller.dart';
import 'package:hyperlocal_app/features/notifications/presentation/screens/notification_settings_screen.dart';

class _StubAuthController extends AuthController {
  final AuthStatus status;

  _StubAuthController(this.status);

  @override
  AuthState build() => AuthState(status: status);
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required AuthStatus status,
  NotificationPreferences? preferences,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      localStorageDriverProvider.overrideWithValue(InMemoryStorageDriver()),
      authControllerProvider.overrideWith(() => _StubAuthController(status)),
      notificationsRepositoryProvider.overrideWithValue(
        MockNotificationRepository(
          delay: Duration.zero,
          preferences: preferences ?? NotificationPreferences.defaults,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: NotificationSettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('offers exactly the toggles the backend can store', (
    tester,
  ) async {
    await _pump(tester, status: AuthStatus.authenticated);

    // Supported: the three gated categories + the two channels.
    expect(find.byKey(const Key('notifPriceUpdates')), findsOneWidget);
    expect(find.byKey(const Key('notifAvailabilityUpdates')), findsOneWidget);
    expect(find.byKey(const Key('notifOffers')), findsOneWidget);
    expect(find.byKey(const Key('notifEmailChannel')), findsOneWidget);
    expect(find.byKey(const Key('notifSmsChannel')), findsOneWidget);
    expect(find.byKey(const Key('notifMasterSwitch')), findsOneWidget);
  });

  testWidgets('does NOT offer toggles the backend has no column for', (
    tester,
  ) async {
    await _pump(tester, status: AuthStatus.authenticated);

    // There is no `shop_updates` and no `system_notifications` column in
    // `notification_preferences`. A switch for either would look like control
    // while doing nothing once the customer is signed in, so neither exists.
    expect(find.byKey(const Key('notifShopUpdates')), findsNothing);
    expect(find.byKey(const Key('notifSystemNotifications')), findsNothing);
    expect(find.text('Shop updates'), findsNothing);
    expect(find.text('System notifications'), findsNothing);
  });

  testWidgets('toggling price updates writes through to the controller', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      status: AuthStatus.authenticated,
    );
    final before = container
        .read(notificationPreferencesControllerProvider)
        .preferences
        .priceAlerts;

    await tester.tap(find.byKey(const Key('notifPriceUpdates')));
    await tester.pumpAndSettle();

    final after = container
        .read(notificationPreferencesControllerProvider)
        .preferences
        .priceAlerts;
    expect(after, isNot(before));
  });

  testWidgets('the offers switch drives both backend fields', (tester) async {
    // Start from promotional=false so the switch renders "off".
    final container = await _pump(
      tester,
      status: AuthStatus.authenticated,
      preferences: const NotificationPreferences(
        promotional: false,
        dealAlerts: false,
      ),
    );

    await tester.tap(find.byKey(const Key('notifOffers')));
    await tester.pumpAndSettle();

    final prefs = container
        .read(notificationPreferencesControllerProvider)
        .preferences;
    // One switch, two columns — they must never disagree.
    expect(prefs.promotional, isTrue);
    expect(prefs.dealAlerts, isTrue);
  });

  testWidgets('guests are told their choices are device-local', (tester) async {
    await _pump(tester, status: AuthStatus.guest);

    expect(find.text('Sign in to sync your choices'), findsOneWidget);
    // The switches are still usable — a guest is browsing, just not syncing.
    expect(find.byKey(const Key('notifPriceUpdates')), findsOneWidget);
  });

  testWidgets('section labels describe what each group controls', (
    tester,
  ) async {
    await _pump(tester, status: AuthStatus.authenticated);

    expect(find.text('ON THIS DEVICE'), findsOneWidget);
    expect(find.text('WHAT YOU GET ALERTED ABOUT'), findsOneWidget);
    expect(find.text('OTHER DELIVERY CHANNELS'), findsOneWidget);
  });
}
