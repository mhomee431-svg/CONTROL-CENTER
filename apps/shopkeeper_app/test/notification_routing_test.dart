import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/router/route_names.dart';
import 'package:hyperlocal_shopkeeper_app/features/notifications/domain/notification_models.dart';

/// Helper: build a notification from a raw backend type + optional deep link.
ShopkeeperNotification _notification({
  int id = 1,
  required String type,
  String title = '',
  String? deepLink,
  Map<String, dynamic>? payload,
}) =>
    ShopkeeperNotification(
      id: id,
      title: title,
      body: '',
      type: type,
      isRead: false,
      createdAt: DateTime(2026, 9, 18, 21, 19),
      deepLink: deepLink,
      payload: payload,
    );

void main() {
  group('notificationRouteTarget', () {
    test('Low Stock → Inventory (Routes.lowStock)', () {
      final n = _notification(
        type: 'INVENTORY_LOW',
        title: 'Low stock: Atta',
      );
      expect(notificationRouteTarget(n), Routes.lowStock);
    });

    test('Import Failed → Import Result (Routes.importResult)', () {
      // The backend sends IMPORT type with a `job_id` payload for both
      // completed and failed imports. A failed import is the case that matters
      // most: the shopkeeper must land on THAT job's outcome, not on a list
      // they have to re-scan to find it.
      final n = _notification(
        type: 'IMPORT',
        title: 'Import failed',
        deepLink: 'hyperlocal://shopkeeper/imports/42',
        payload: {'job_id': 42, 'status': 'FAILED', 'failed_rows': 3},
      );
      expect(notificationRouteTarget(n), Routes.importResult);
    });

    test('Import completed (success) also → Import Result', () {
      final n = _notification(
        type: 'IMPORT',
        title: 'Import completed',
        payload: {'job_id': 99, 'status': 'COMPLETED', 'processed_rows': 50},
      );
      expect(notificationRouteTarget(n), Routes.importResult);
    });

    test('Import with NO usable job id falls back to Import history', () {
      // A payload that cannot name a real job must never become a request for
      // a fabricated one. History is the honest destination: it still shows
      // every job, so the tap is useful rather than dead.
      for (final payload in <Map<String, dynamic>?>[
        null,
        <String, dynamic>{},
        <String, dynamic>{'job_id': null},
        <String, dynamic>{'job_id': 0},
        <String, dynamic>{'job_id': -7},
        <String, dynamic>{'job_id': '42'}, // right digits, wrong type
        <String, dynamic>{'job_id': 4.5}, // not a whole number
      ]) {
        final n = _notification(
          type: 'IMPORT',
          title: 'Import failed',
          payload: payload,
        );
        expect(
          notificationRouteTarget(n),
          Routes.importHistory,
          reason: 'payload $payload must not resolve to a fabricated job',
        );
      }
    });

    test('a whole-number job id sent as a double is accepted', () {
      // JSON has one number type, so an id can arrive as 42.0. `payloadInt`
      // rounds it deliberately rather than rejecting a real job over a
      // transport detail.
      final n = _notification(
        type: 'IMPORT',
        payload: {'job_id': 42.0},
      );
      expect(n.payloadInt('job_id'), 42);
      expect(notificationRouteTarget(n), Routes.importResult);
    });

    test('Price Update → Product/Price (Routes.priceList)', () {
      // The backend PRICING receipt links into products/{id}; routing must
      // use the VALIDATED type+payload (not the raw link id) so the
      // shopkeeper lands on the pricing surface, never a fabricated item.
      final n = _notification(
        type: 'PRICING',
        title: 'Price update successful',
        deepLink: 'hyperlocal://shopkeeper/products/7',
        payload: {'shop_product_id': 7},
      );
      expect(notificationRouteTarget(n), Routes.priceList);
    });

    test('Pricing type → Product/Price (Routes.priceList)', () {
      final n = _notification(
        type: 'PRICING',
        title: 'Bulk pricing applied',
      );
      expect(notificationRouteTarget(n), Routes.priceList);
    });

    test('Profile Issue → Profile (Routes.shopProfile)', () {
      final n = _notification(
        type: 'ACCOUNT',
        title: 'Profile issue detected',
        payload: {'event': 'PROFILE_UPDATED'},
      );
      expect(notificationRouteTarget(n), Routes.shopProfile);
    });

    test('Account settings change → Shop settings (Routes.shopSettings)', () {
      // SETTINGS_UPDATED is refined by the validated payload event: the
      // generic account tab would be less useful than the settings screen.
      final n = _notification(
        type: 'ACCOUNT',
        title: 'Settings updated',
        payload: {'event': 'SETTINGS_UPDATED'},
      );
      expect(notificationRouteTarget(n), Routes.shopSettings);
    });

    test('ACCOUNT with unknown event → default Route.account', () {
      final n = _notification(
        type: 'ACCOUNT',
        title: 'Account change',
        payload: {'event': 'UNKNOWN_EVENT'},
      );
      expect(notificationRouteTarget(n), Routes.account);
    });

    test('ACCOUNT with no payload → default Route.account', () {
      final n = _notification(type: 'ACCOUNT', title: 'Account update');
      expect(notificationRouteTarget(n), Routes.account);
    });
  });

  group('notificationRouteTarget deep-link precedence', () {
    test('inventory deep-link section routes to the inventory list', () {
      // Known type + matching section: both signals agree.
      final n = _notification(
        type: 'INVENTORY_UPDATE',
        title: 'Stock updated',
        deepLink: 'hyperlocal://shopkeeper/inventory/11',
      );
      expect(notificationRouteTarget(n), Routes.inventoryList);
    });

    test('type wins over a stale deep link — never navigate raw ids', () {
      // Even though the link points at products/{id}, the validated
      // PRICE_UPDATE type routes to the pricing surface. The id is never
      // pushed into a route; item screens need a full object via `extra`.
      final n = _notification(
        type: 'PRICE_UPDATE',
        title: 'Price changed',
        deepLink: 'hyperlocal://shopkeeper/products/7',
      );
      expect(notificationRouteTarget(n), Routes.priceList);
    });

    test('unknown type falls back to the deep-link section', () {
      // A type the backend added after this build: the section is the only
      // remaining signal, so it is used as a module-level fallback.
      final n = _notification(
        type: 'BRAND_NEW_TYPE',
        title: 'Something new',
        deepLink: 'hyperlocal://shopkeeper/imports/42',
      );
      expect(notificationRouteTarget(n), Routes.importHistory);
    });

    test('unknown deep link section falls back to type-based routing', () {
      final n = _notification(
        type: 'INVENTORY_LOW',
        title: 'Stock low',
        deepLink: 'hyperlocal://shopkeeper/unknown-section',
      );
      // Deep link section is unknown → type routing already won first.
      expect(notificationRouteTarget(n), Routes.lowStock);
    });

    test('non-matching deep link prefix falls back to type-based routing', () {
      final n = _notification(
        type: 'IMPORT',
        title: 'Import done',
        deepLink: 'https://other.app/imports/1',
      );
      expect(notificationRouteTarget(n), Routes.importHistory);
    });
  });

  group('notificationRouteTarget default fallback', () {
    test('unrecognised type → Routes.notificationDetail', () {
      final n = _notification(type: 'BRAND_NEW_TYPE', title: '???');
      expect(notificationRouteTarget(n), Routes.notificationDetail);
    });

    test('empty deep link + known type still routes by type', () {
      final n = _notification(type: 'SUPPORT', title: 'Support ticket');
      expect(notificationRouteTarget(n), Routes.support);
    });
  });

  group('notificationRouteTarget tab targets use context.go', () {
    test('products type → Routes.products (a shell tab)', () {
      expect(
        notificationRouteTarget(
          _notification(type: 'PRODUCT', title: 'Product update'),
        ),
        Routes.products,
      );
    });

    test('unknown type + dashboard deep link → Routes.dashboard', () {
      // The type takes precedence when known; the dashboard section only
      // applies as a fallback when the backend type is unrecognised.
      final n = _notification(
        type: 'BRAND_NEW_TYPE',
        deepLink: 'hyperlocal://shopkeeper/dashboard',
      );
      expect(notificationRouteTarget(n), Routes.dashboard);
    });
  });
}
