import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/catalog/approved_categories.dart';
import 'package:hyperlocal_app/features/notifications/data/fcm_notification_service.dart';
import 'package:hyperlocal_app/features/notifications/domain/models/app_notification.dart';
import 'package:hyperlocal_app/features/notifications/presentation/controllers/deep_link_handler.dart';

void main() {
  test('approved categories exclude grocery and keep restaurants', () {
    expect(ApprovedCategories.names, isNot(contains('Groceries')));
    expect(ApprovedCategories.names, isNot(contains('Grocery')));
    expect(ApprovedCategories.names, contains('Restaurants'));
    expect(ApprovedCategories.names, contains('Pharmacy & Healthcare'));
    expect(ApprovedCategories.isApproved('Hardware'), isTrue);
    expect(ApprovedCategories.isApproved('Electronics'), isFalse);
  });

  test('mock FCM service returns a token and topic calls succeed', () async {
    final service = MockFcmNotificationService();
    await service.initialize();
    expect(await service.getToken(), 'mock_fcm_token_xyz_123');
    await service.subscribeToTopic('offers');
    await service.unsubscribeFromTopic('offers');
  });

  test('FCM opened payload with product id navigates via deep link', () {
    final notification = AppNotification.fromJson({
      'id': 'm1',
      'title': 'Price drop',
      'body': 'Nearby shop dropped the price',
      'created_at': DateTime(2026, 1, 1).toIso8601String(),
      'type': 'price_drop',
      'payload': {'product_id': 'prod_42'},
    });
    final resolution = resolveNotificationDeepLink(notification);
    expect(resolution.action, DeepLinkAction.navigate);
    expect(resolution.path, '/product/prod_42');
  });

  test('FCM opened payload with shop id maps to shop route', () {
    final notification = AppNotification.fromJson({
      'id': 'push-1',
      'title': 'Shop update',
      'body': 'Hours changed',
      'created_at': DateTime.now().toIso8601String(),
      'type': 'shop_update',
      'payload': {'shop_id': 'shop_3'},
    });
    final resolution = resolveNotificationDeepLink(notification);
    expect(resolution.action, DeepLinkAction.navigate);
    expect(resolution.path, '/shop/shop_3');
  });
}
