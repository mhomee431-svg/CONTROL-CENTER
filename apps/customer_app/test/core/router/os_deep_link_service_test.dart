import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/router/app_link_source.dart';
import 'package:hyperlocal_app/core/router/os_deep_link_service.dart';
import 'package:hyperlocal_app/features/notifications/presentation/controllers/pending_deep_link_controller.dart';

void main() {
  group('OS deep link service', () {
    test('queues the cold-start link the app was launched with', () async {
      final source = FakeAppLinkSource(
        initialLink: Uri.parse('passly://product/abc123'),
      );
      addTearDown(source.dispose);
      final container = ProviderContainer(
        overrides: [appLinkSourceProvider.overrideWithValue(source)],
      );
      addTearDown(container.dispose);

      container.read(osDeepLinkServiceProvider);
      // The cold-start read is awaited inside `start()`, so let it settle.
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(pendingDeepLinkControllerProvider)?.path,
        'passly://product/abc123',
      );
    });

    test('queues a link that arrives while the app is already open', () async {
      final source = FakeAppLinkSource();
      addTearDown(source.dispose);
      final container = ProviderContainer(
        overrides: [appLinkSourceProvider.overrideWithValue(source)],
      );
      addTearDown(container.dispose);

      container.read(osDeepLinkServiceProvider);
      await Future<void>.delayed(Duration.zero);

      // Nothing yet: no link has arrived.
      expect(container.read(pendingDeepLinkControllerProvider), isNull);

      source.emit(Uri.parse('https://passly.app/shop/shop-9'));
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(pendingDeepLinkControllerProvider)?.path,
        'https://passly.app/shop/shop-9',
      );
    });

    test('an OS link carries no notification id', () async {
      final source = FakeAppLinkSource(
        initialLink: Uri.parse('passly://shop/s1'),
      );
      addTearDown(source.dispose);
      final container = ProviderContainer(
        overrides: [appLinkSourceProvider.overrideWithValue(source)],
      );
      addTearDown(container.dispose);

      container.read(osDeepLinkServiceProvider);
      await Future<void>.delayed(Duration.zero);

      // Only an FCM tap has a notification to mark read; a browser or share
      // link has none, and inventing an id would mark an unrelated row read.
      expect(
        container.read(pendingDeepLinkControllerProvider)?.notificationId,
        isEmpty,
      );
    });

    test('the newest link wins, so a stale tap cannot replay', () async {
      final source = FakeAppLinkSource();
      addTearDown(source.dispose);
      final container = ProviderContainer(
        overrides: [appLinkSourceProvider.overrideWithValue(source)],
      );
      addTearDown(container.dispose);

      container.read(osDeepLinkServiceProvider);
      await Future<void>.delayed(Duration.zero);

      source.emit(Uri.parse('passly://product/first'));
      await Future<void>.delayed(Duration.zero);
      source.emit(Uri.parse('passly://product/second'));
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(pendingDeepLinkControllerProvider)?.path,
        'passly://product/second',
      );
    });
  });

  group('FakeAppLinkSource', () {
    test('coldStartLink is re-readable, matching the platform contract', () async {
      final source = FakeAppLinkSource();
      addTearDown(source.dispose);

      expect(await source.initialLink(), isNull);

      source.coldStartLink = Uri.parse('passly://product/x1');
      expect(
        await source.initialLink(),
        Uri.parse('passly://product/x1'),
        reason: 'a re-read must report the same link, not consume it',
      );
    });
  });
}