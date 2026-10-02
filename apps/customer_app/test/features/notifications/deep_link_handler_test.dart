import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/features/notifications/domain/models/app_notification.dart';
import 'package:hyperlocal_app/features/notifications/presentation/controllers/deep_link_handler.dart';

AppNotification _withLink(NotificationDeepLink link) => AppNotification(
  id: 'x',
  title: 't',
  body: 'b',
  timestamp: DateTime(2026),
  deepLink: link,
);

void main() {
  group('resolveNotificationDeepLink', () {
    test('product links map to /product/:id', () {
      final resolution = resolveNotificationDeepLink(
        _withLink(
          const NotificationDeepLink(
            targetType: DeepLinkTargetType.product,
            targetId: 'prod_1',
          ),
        ),
      );
      expect(resolution.action, DeepLinkAction.navigate);
      expect(resolution.path, '/product/prod_1');
    });

    test('shop links map to /shop/:id', () {
      final resolution = resolveNotificationDeepLink(
        _withLink(
          const NotificationDeepLink(
            targetType: DeepLinkTargetType.shop,
            targetId: 'shop_3',
          ),
        ),
      );
      expect(resolution.action, DeepLinkAction.navigate);
      expect(resolution.path, '/shop/shop_3');
    });

    test('offer links route to the registered unavailable screen', () {
      final resolution = resolveNotificationDeepLink(
        _withLink(
          const NotificationDeepLink(
            targetType: DeepLinkTargetType.offer,
            targetId: 'offer_9',
          ),
        ),
      );
      // The offer route is now registered, so the link resolves to a real
      // screen that explains the offer cannot be opened, rather than a
      // transient snackbar over the inbox. The customer still never sees a
      // 404 and still never sees a falsely-successful "offer opened".
      expect(resolution.action, DeepLinkAction.navigate);
      expect(resolution.path, '/offer/unavailable');
      expect(resolution.message, isNull);
    });

    test('expired links degrade to unavailable with message', () {
      final now = DateTime(2026, 8, 24);
      final resolution = resolveNotificationDeepLink(
        _withLink(
          NotificationDeepLink(
            targetType: DeepLinkTargetType.offer,
            targetId: 'offer_9',
            expiresAt: now.subtract(const Duration(hours: 1)),
          ),
        ),
      );
      expect(resolution.action, DeepLinkAction.unavailable);
    });

    test('malformed ids never produce a route', () {
      final resolution = resolveNotificationDeepLink(
        _withLink(
          const NotificationDeepLink(
            targetType: DeepLinkTargetType.shop,
            targetId: '../etc/passwd',
          ),
        ),
      );
      expect(resolution.action, DeepLinkAction.unavailable);
      expect(resolution.path, isNull);
    });

    test('notifications without a link resolve to none (just mark read)', () {
      final resolution = resolveNotificationDeepLink(
        _withLink(const NotificationDeepLink()),
      );
      expect(resolution.action, DeepLinkAction.none);
    });
  });
}
