import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/features/notifications/data/mock_notification_repository.dart';
import 'package:hyperlocal_app/features/notifications/domain/models/notification_preferences.dart';
import 'package:hyperlocal_app/features/notifications/presentation/controllers/notification_preferences_controller.dart';
import 'package:hyperlocal_app/features/notifications/domain/notification_repository.dart';

void main() {
  group('NotificationPreferencesController', () {
    late ProviderContainer container;
    late MockNotificationRepository repository;

    setUp(() {
      repository = MockNotificationRepository(delay: Duration.zero);
      container = ProviderContainer(
        overrides: [
          notificationsRepositoryProvider.overrideWithValue(repository),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    Future<void> settle() async {
      // Trigger build + microtask load, then poll until the load lands.
      container.read(notificationPreferencesControllerProvider);
      for (var i = 0; i < 100; i++) {
        if (!container
            .read(notificationPreferencesControllerProvider)
            .isLoading) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    NotificationPreferences prefs() =>
        container.read(notificationPreferencesControllerProvider).preferences;

    test('loads preferences from the repository', () async {
      final custom = const NotificationPreferences().copyWith(
        smsEnabled: true,
        promotional: true,
      );
      await repository.updatePreferences(custom);

      await settle();

      expect(prefs().smsEnabled, isTrue);
      expect(prefs().promotional, isTrue);
      expect(
        container.read(notificationPreferencesControllerProvider).isLoading,
        isFalse,
      );
    });

    test('type/channel updates persist through the repository', () async {
      await settle();

      await container
          .read(notificationPreferencesControllerProvider.notifier)
          .setPriceAlerts(false);

      expect(prefs().priceAlerts, isFalse);
      expect((await repository.getPreferences()).priceAlerts, isFalse);
    });

    test('setOffers moves promotional and dealAlerts together', () async {
      await settle();
      final controller = container.read(
        notificationPreferencesControllerProvider.notifier,
      );

      // "Offers and deals" is one switch over two columns. Enabling it must
      // set BOTH, otherwise the backend would still suppress some offers.
      await controller.setOffers(true);
      expect(prefs().promotional, isTrue);
      expect(prefs().dealAlerts, isTrue);

      // Disabling must clear BOTH, or the switch would read "off" while
      // the backend kept sending deals.
      await controller.setOffers(false);
      expect(prefs().promotional, isFalse);
      expect(prefs().dealAlerts, isFalse);
    });

    test('failed save rolls back and surfaces an error', () async {
      final failing = ProviderContainer(
        overrides: [
          notificationsRepositoryProvider.overrideWithValue(
            MockNotificationRepository(
              delay: Duration.zero,
              failureMode: MockFailureMode.preferences,
            ),
          ),
        ],
      );
      addTearDown(failing.dispose);

      // Initial load fails -> defaults are kept.
      failing.read(notificationPreferencesControllerProvider);
      for (var i = 0; i < 100; i++) {
        if (!failing
            .read(notificationPreferencesControllerProvider)
            .isLoading) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      await failing
          .read(notificationPreferencesControllerProvider.notifier)
          .setSms(true);

      final state = failing.read(notificationPreferencesControllerProvider);
      expect(state.preferences.smsEnabled, isFalse); // rolled back
      expect(state.error, isNotNull);
    });
  });
}
