import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/features/notifications/domain/models/app_notification.dart';

void main() {
  group('NotificationType', () {
    test('maps backend type strings', () {
      expect(NotificationType.fromApi('price_alert'), NotificationType.priceDrop);
      expect(
        NotificationType.fromApi('availability_alert'),
        NotificationType.productAvailable,
      );
      expect(NotificationType.fromApi('promotional'), NotificationType.offer);
      expect(NotificationType.fromApi('deal_alert'), NotificationType.offer);
      expect(NotificationType.fromApi('shop_update'), NotificationType.shopUpdate);
      expect(NotificationType.fromApi('order_update'), NotificationType.orderUpdate);
      expect(NotificationType.fromApi('system'), NotificationType.system);
    });

    test('unknown values degrade safely to system', () {
      expect(NotificationType.fromApi(null), NotificationType.system);
      expect(NotificationType.fromApi('mystery'), NotificationType.system);
      expect(NotificationType.fromApi(''), NotificationType.system);
    });

    test('toApi round-trips', () {
      for (final type in NotificationType.values) {
        expect(NotificationType.fromApi(type.toApi()), type);
      }
    });
  });

  group('NotificationDeepLink.fromPayload', () {
    test('parses JSON string payload with product id', () {
      final link = NotificationDeepLink.fromPayload(
        '{"product_id": 42, "shop_id": 7}',
      );
      expect(link.targetType, DeepLinkTargetType.product);
      expect(link.targetId, '42');
      expect(link.isValid(), isTrue);
    });

    test('parses map payload with shop id', () {
      final link = NotificationDeepLink.fromPayload({'shop_id': 'shop_abc'});
      expect(link.targetType, DeepLinkTargetType.shop);
      expect(link.targetId, 'shop_abc');
    });

    test('prefers product over offer/shop', () {
      final link = NotificationDeepLink.fromPayload({
        'offer_id': 'o1',
        'product_id': 'p1',
        'shop_id': 's1',
      });
      expect(link.targetType, DeepLinkTargetType.product);
    });

    test('resolves offer ids', () {
      final link = NotificationDeepLink.fromPayload({'offer_id': 'o9'});
      expect(link.targetType, DeepLinkTargetType.offer);
      expect(link.targetId, 'o9');
    });

    test('empty payload yields non-navigable link', () {
      final link = NotificationDeepLink.fromPayload(null);
      expect(link.targetType, DeepLinkTargetType.none);
      expect(link.isValid(), isFalse);

      expect(NotificationDeepLink.fromPayload('').isValid(), isFalse);
      expect(
        NotificationDeepLink.fromPayload({'unrelated': 'x'}).targetType,
        DeepLinkTargetType.none,
      );
    });

    test('malformed JSON string yields non-navigable link', () {
      expect(NotificationDeepLink.fromPayload('{not json').isValid(), isFalse);
    });

    test('non-map JSON yields non-navigable link', () {
      expect(NotificationDeepLink.fromPayload('[1,2,3]').isValid(), isFalse);
    });
  });

  group('NotificationDeepLink.isValid', () {
    test('rejects malformed ids that could alter route structure', () {
      expect(
        const NotificationDeepLink(
          targetType: DeepLinkTargetType.product,
          targetId: '../../admin',
        ).isValid(),
        isFalse,
      );
      expect(
        const NotificationDeepLink(
          targetType: DeepLinkTargetType.product,
          targetId: 'a b',
        ).isValid(),
        isFalse,
      );
      expect(
        const NotificationDeepLink(
          targetType: DeepLinkTargetType.product,
          targetId: '',
        ).isValid(),
        isFalse,
      );
    });

    test('accepts sane ids', () {
      expect(
        const NotificationDeepLink(
          targetType: DeepLinkTargetType.product,
          targetId: 'prod_123-xyz',
        ).isValid(),
        isTrue,
      );
    });

    test('expired links are invalid, future links valid', () {
      final now = DateTime(2026, 8, 24, 12);
      final expired = NotificationDeepLink(
        targetType: DeepLinkTargetType.offer,
        targetId: 'o1',
        expiresAt: now.subtract(const Duration(minutes: 1)),
      );
      expect(expired.isValid(now: now), isFalse);

      final fresh = NotificationDeepLink(
        targetType: DeepLinkTargetType.offer,
        targetId: 'o1',
        expiresAt: now.add(const Duration(hours: 1)),
      );
      expect(fresh.isValid(now: now), isTrue);
    });
  });

  group('AppNotification.fromJson', () {
    test('parses full backend contract shape', () {
      final n = AppNotification.fromJson({
        'id': 1,
        'title': 'Price drop alert',
        'body': 'Paracetamol is cheaper',
        'type': 'price_alert',
        'is_read': false,
        'payload': '{"product_id": 1}',
        'created_at': '2026-08-19T10:00:00Z',
      });
      expect(n.id, '1');
      expect(n.type, NotificationType.priceDrop);
      expect(n.isRead, isFalse);
      expect(n.deepLink.targetType, DeepLinkTargetType.product);
      expect(n.timestamp, DateTime.utc(2026, 8, 19, 10));
    });

    test('tolerates missing fields', () {
      final n = AppNotification.fromJson({});
      expect(n.id, '');
      expect(n.title, '');
      expect(n.type, NotificationType.system);
      expect(n.isRead, isFalse);
      expect(n.deepLink.isValid(), isFalse);
    });
  });

  test('copyWith only changes read state', () {
    final original = AppNotification(
      id: 'n1',
      title: 't',
      body: 'b',
      timestamp: DateTime(2026),
      type: NotificationType.offer,
      deepLink: const NotificationDeepLink(
        targetType: DeepLinkTargetType.offer,
        targetId: 'o',
      ),
    );
    final updated = original.copyWith(isRead: true);
    expect(updated.isRead, isTrue);
    expect(updated.id, original.id);
    expect(updated.title, original.title);
    expect(updated.deepLink, original.deepLink);
    expect(updated == original.copyWith(isRead: true), isTrue);
  });
}
