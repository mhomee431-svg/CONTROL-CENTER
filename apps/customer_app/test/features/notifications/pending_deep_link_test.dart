import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/storage/local_storage_driver.dart';
import 'package:hyperlocal_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:hyperlocal_app/features/notifications/presentation/controllers/pending_deep_link_controller.dart';
import 'package:hyperlocal_app/features/notifications/presentation/controllers/pending_deep_link_drain.dart';

void main() {
  group('isRouterReadyForDeepLink', () {
    test('blocked while auth has not resolved', () {
      expect(
        isRouterReadyForDeepLink(
          authStatus: AuthStatus.initial,
          onboardingCompleted: true,
        ),
        isFalse,
      );
      expect(
        isRouterReadyForDeepLink(
          authStatus: AuthStatus.loading,
          onboardingCompleted: true,
        ),
        isFalse,
      );
    });

    test('blocked while the onboarding flag is still loading', () {
      expect(
        isRouterReadyForDeepLink(
          authStatus: AuthStatus.guest,
          onboardingCompleted: null,
        ),
        isFalse,
      );
    });

    test('ready once auth and onboarding have both resolved', () {
      for (final status in [
        AuthStatus.guest,
        AuthStatus.authenticated,
        AuthStatus.unauthenticated,
        AuthStatus.sessionExpired,
      ]) {
        expect(
          isRouterReadyForDeepLink(
            authStatus: status,
            onboardingCompleted: true,
          ),
          isTrue,
          reason: '$status should allow a queued deep link through',
        );
      }
    });

    test(
      'onboarding not yet completed still blocks a first-launch deep link',
      () {
        // The redirect sends everything to /onboarding while the tour is
        // pending, so navigating now would be undone immediately.
        expect(
          isRouterReadyForDeepLink(
            authStatus: AuthStatus.guest,
            onboardingCompleted: false,
          ),
          isFalse,
        );
      },
    );
  });

  group('PendingDeepLinkController', () {
    late ProviderContainer container;
    late InMemoryStorageDriver storage;

    setUp(() {
      storage = InMemoryStorageDriver();
      container = ProviderContainer(
        overrides: [localStorageDriverProvider.overrideWithValue(storage)],
      );
    });

    tearDown(() => container.dispose());

    PendingDeepLinkController controller() =>
        container.read(pendingDeepLinkControllerProvider.notifier);

    test('an enqueued link is held, not navigated', () async {
      await controller().enqueue('/product/42', notificationId: 'n1');
      final state = container.read(pendingDeepLinkControllerProvider);
      expect(state!.path, '/product/42');
      expect(state.notificationId, 'n1');
    });

    test('the newest tap wins', () async {
      await controller().enqueue('/product/1');
      await controller().enqueue('/shop/9');
      expect(
        container.read(pendingDeepLinkControllerProvider)!.path,
        '/shop/9',
      );
    });

    test('empty paths are ignored', () async {
      await controller().enqueue('');
      expect(container.read(pendingDeepLinkControllerProvider), isNull);
    });

    test('take consumes the link exactly once', () async {
      await controller().enqueue('/product/42', notificationId: 'n1');
      final taken = controller().take();
      expect(taken!.path, '/product/42');
      expect(container.read(pendingDeepLinkControllerProvider), isNull);
      // A second take must not replay the same navigation.
      expect(controller().take(), isNull);
    });

    test('a stale link is discarded instead of replayed', () async {
      final stale = PendingDeepLink(
        path: '/product/42',
        notificationId: 'n1',
        queuedAt: DateTime.now().subtract(const Duration(hours: 3)),
      );
      expect(stale.isExpired(), isTrue);

      await controller().enqueue('/product/42');
      // Force the expired shape through the real controller API.
      final expired = controller().take(
        now: DateTime.now().add(const Duration(hours: 3)),
      );
      expect(expired, isNull);
      expect(container.read(pendingDeepLinkControllerProvider), isNull);
    });

    test('survives process death (terminated-state tap)', () async {
      await controller().enqueue('/product/42', notificationId: 'n1');
      // The write is what carries the tap across a cold start.
      expect(await storage.getString(pendingDeepLinkStorageKey), isNotNull);

      // A brand-new container models the next app launch.
      final relaunched = ProviderContainer(
        overrides: [localStorageDriverProvider.overrideWithValue(storage)],
      );
      addTearDown(relaunched.dispose);

      await relaunched
          .read(pendingDeepLinkControllerProvider.notifier)
          .restore();
      final restored = relaunched.read(pendingDeepLinkControllerProvider);
      expect(restored!.path, '/product/42');
      expect(restored.notificationId, 'n1');
    });

    test('corrupt persisted payloads never block start-up', () async {
      await storage.setString(pendingDeepLinkStorageKey, 'not-json{{');
      await controller().restore();
      expect(container.read(pendingDeepLinkControllerProvider), isNull);
    });

    test('a link that aged out while closed is dropped on restore', () async {
      // The stored payload must be genuinely stale: `restore()` reads
      // `queued_at` straight out of the payload, so writing the fresh
      // round-trip here would prove nothing. A missing `queued_at` also
      // defaults to *now*, which makes the link fresh rather than expired.
      final old = PendingDeepLink(
        path: '/product/42',
        notificationId: 'n1',
        queuedAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      await storage.setString(
        pendingDeepLinkStorageKey,
        jsonEncode(old.toJson()),
      );
      // Sanity: the stale payload round-trips as expired.
      expect(PendingDeepLink.fromJson(old.toJson())!.isExpired(), isTrue);

      await controller().restore();
      // Aged out, so nothing is queued and the stale payload is cleared.
      expect(container.read(pendingDeepLinkControllerProvider), isNull);
    });
  });
}
