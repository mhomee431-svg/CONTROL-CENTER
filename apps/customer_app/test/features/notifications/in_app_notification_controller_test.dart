import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/features/notifications/domain/models/app_notification.dart';
import 'package:hyperlocal_app/features/notifications/domain/models/notification_preferences.dart';
import 'package:hyperlocal_app/features/notifications/presentation/controllers/in_app_notification_controller.dart';

AppNotification _n(
  String id, {
  NotificationType type = NotificationType.priceDrop,
}) => AppNotification(
  id: id,
  title: 'title $id',
  body: 'body $id',
  timestamp: DateTime(2026, 8, 24),
  type: type,
);

void main() {
  group('decideInAppPresentation', () {
    test('device master switch off silences every type', () {
      for (final type in NotificationType.values) {
        expect(
          decideInAppPresentation(
            type: type,
            pushEnabled: false,
            preferences: NotificationPreferences.defaults,
          ),
          InAppPresentation.silent,
          reason: '$type must not surface when push is off',
        );
      }
    });

    test('account master switch off silences every type', () {
      for (final type in NotificationType.values) {
        expect(
          decideInAppPresentation(
            type: type,
            pushEnabled: true,
            preferences: const NotificationPreferences(pushEnabled: false),
          ),
          InAppPresentation.silent,
          reason: '$type must not surface when account push is off',
        );
      }
    });

    test('per-type opt-outs are honoured individually', () {
      const base = NotificationPreferences.defaults;
      expect(
        decideInAppPresentation(
          type: NotificationType.priceDrop,
          pushEnabled: true,
          preferences: base.copyWith(priceAlerts: false),
        ),
        InAppPresentation.silent,
      );
      expect(
        decideInAppPresentation(
          type: NotificationType.productAvailable,
          pushEnabled: true,
          preferences: base.copyWith(availabilityAlerts: false),
        ),
        InAppPresentation.silent,
      );
      // Shop updates are deliberately NOT asserted here: `NotificationPreferences`
      // has no `shop_updates` field because the backend has no such column, so a
      // client-side opt-out would desync from what the server actually sends.
      // Their gating is covered by the dedicated test below.
      // An offer needs either promotional OR dealAlerts to be worth showing.
      final noOffers = base.copyWith(promotional: false, dealAlerts: false);
      expect(
        decideInAppPresentation(
          type: NotificationType.offer,
          pushEnabled: true,
          preferences: noOffers,
        ),
        InAppPresentation.silent,
      );
      expect(
        decideInAppPresentation(
          type: NotificationType.offer,
          pushEnabled: true,
          preferences: noOffers.copyWith(dealAlerts: true),
        ),
        InAppPresentation.snackBar,
      );
    });

    test('shop updates follow the master switch only (no backend gate)', () {
      // The backend has no `shop_updates` column, so the app must NOT offer
      // an opt-out that would desync from what the backend actually sends.
      expect(
        decideInAppPresentation(
          type: NotificationType.shopUpdate,
          pushEnabled: true,
          preferences: NotificationPreferences.defaults,
        ),
        InAppPresentation.banner,
      );
      // It is still silenced by the master switches, which DO exist.
      expect(
        decideInAppPresentation(
          type: NotificationType.shopUpdate,
          pushEnabled: false,
          preferences: NotificationPreferences.defaults,
        ),
        InAppPresentation.silent,
      );
    });

    test('system messages follow the master switch only', () {
      // `SYSTEM` is Audience.ADMIN and documented as never gated.
      expect(
        decideInAppPresentation(
          type: NotificationType.system,
          pushEnabled: true,
          preferences: NotificationPreferences.defaults,
        ),
        InAppPresentation.snackBar,
      );
      expect(
        decideInAppPresentation(
          type: NotificationType.system,
          pushEnabled: false,
          preferences: NotificationPreferences.defaults,
        ),
        InAppPresentation.silent,
      );
    });

    test('informational alerts use a non-interrupting banner', () {
      const prefs = NotificationPreferences.defaults;
      for (final type in [
        NotificationType.priceDrop,
        NotificationType.productAvailable,
        NotificationType.shopUpdate,
      ]) {
        expect(
          decideInAppPresentation(
            type: type,
            pushEnabled: true,
            preferences: prefs,
          ),
          InAppPresentation.banner,
          reason: '$type must not interrupt the customer',
        );
      }
    });

    test('only transactional updates earn a modal dialog', () {
      // A dialog is the one truly interrupting tier, so it is reserved for
      // the message the customer is actively waiting on.
      for (final type in NotificationType.values) {
        final presentation = decideInAppPresentation(
          type: type,
          pushEnabled: true,
          preferences: NotificationPreferences.defaults.copyWith(
            promotional: true,
          ),
        );
        expect(
          presentation == InAppPresentation.dialog,
          type == NotificationType.orderUpdate,
          reason: '$type dialog tier is wrong',
        );
      }
    });
  });

  group('InAppNotificationController', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() => container.dispose());

    InAppNotificationController controller() =>
        container.read(inAppNotificationControllerProvider.notifier);

    test('first message goes straight on screen', () {
      expect(
        controller().enqueue(_n('a'), presentation: InAppPresentation.banner),
        isTrue,
      );
      final state = container.read(inAppNotificationControllerProvider);
      expect(state.active!.notification.id, 'a');
      expect(state.queue, isEmpty);
    });

    test('silent messages are rejected outright', () {
      expect(
        controller().enqueue(_n('a'), presentation: InAppPresentation.silent),
        isFalse,
      );
      expect(container.read(inAppNotificationControllerProvider).isIdle, isTrue);
    });

    test('duplicate ids never show twice', () {
      controller().enqueue(_n('a'), presentation: InAppPresentation.banner);
      // Same push arriving again (foreground stream + inbox refresh).
      expect(
        controller().enqueue(_n('a'), presentation: InAppPresentation.banner),
        isFalse,
      );
      final state = container.read(inAppNotificationControllerProvider);
      expect(state.active!.notification.id, 'a');
      expect(state.queue, isEmpty);
    });

    test('dismiss promotes the next queued message in order', () {
      controller().enqueue(_n('a'), presentation: InAppPresentation.banner);
      controller().enqueue(_n('b'), presentation: InAppPresentation.banner);
      controller().enqueue(_n('c'), presentation: InAppPresentation.banner);

      controller().dismissActive();
      expect(
        container
            .read(inAppNotificationControllerProvider)
            .active!
            .notification
            .id,
        'b',
      );
      controller().dismissActive();
      expect(
        container
            .read(inAppNotificationControllerProvider)
            .active!
            .notification
            .id,
        'c',
      );
      controller().dismissActive();
      expect(container.read(inAppNotificationControllerProvider).isIdle, isTrue);
    });

    test('waiting queue is capped, dropping the oldest', () {
      controller().enqueue(_n('active'), presentation: InAppPresentation.banner);
      for (final id in ['a', 'b', 'c', 'd', 'e']) {
        controller().enqueue(_n(id), presentation: InAppPresentation.banner);
      }
      final state = container.read(inAppNotificationControllerProvider);
      expect(state.queue.length, InAppNotificationController.maxQueueLength);
      // Newest three survive; a burst never becomes a chore to dismiss.
      expect(
        state.queue.map((i) => i.notification.id).toList(),
        ['c', 'd', 'e'],
      );
    });

    test('clear drops the active message and the whole backlog', () {
      controller().enqueue(_n('a'), presentation: InAppPresentation.banner);
      controller().enqueue(_n('b'), presentation: InAppPresentation.banner);
      controller().clear();
      final state = container.read(inAppNotificationControllerProvider);
      expect(state.isIdle, isTrue);
      expect(state.queue, isEmpty);
    });
  });
}
