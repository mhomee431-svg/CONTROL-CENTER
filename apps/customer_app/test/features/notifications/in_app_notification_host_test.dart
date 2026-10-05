import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/storage/local_storage_driver.dart';
import 'package:hyperlocal_app/features/notifications/data/mock_notification_repository.dart';
import 'package:hyperlocal_app/features/notifications/domain/models/app_notification.dart';
import 'package:hyperlocal_app/features/notifications/domain/notification_repository.dart';
import 'package:hyperlocal_app/features/notifications/presentation/controllers/in_app_notification_controller.dart';
import 'package:hyperlocal_app/features/notifications/presentation/controllers/pending_deep_link_controller.dart';
import 'package:hyperlocal_app/features/notifications/presentation/widgets/in_app_notification_host.dart';

AppNotification _notification({
  required String id,
  NotificationType type = NotificationType.priceDrop,
  String targetId = 'prod_1',
}) => AppNotification(
  id: id,
  title: 'Price drop on Paracetamol',
  body: 'Now ₹12 cheaper at Patna Medical Store',
  timestamp: DateTime(2026, 8, 24),
  type: type,
  deepLink: NotificationDeepLink(
    targetType: DeepLinkTargetType.product,
    targetId: targetId,
  ),
);

/// Hosts [InAppNotificationHost] over a trivial screen and exposes the
/// container so tests can drive the queue the way FCM would.
Future<ProviderContainer> _pumpHost(WidgetTester tester) async {
  final container = ProviderContainer(
    overrides: [
      localStorageDriverProvider.overrideWithValue(InMemoryStorageDriver()),
      notificationsRepositoryProvider.overrideWithValue(
        MockNotificationRepository(delay: Duration.zero),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: InAppNotificationHost(child: Scaffold(body: Text('HomeScreen'))),
      ),
    ),
  );
  return container;
}

void main() {
  testWidgets('a foreground message never interrupts the current screen', (
    tester,
  ) async {
    final container = await _pumpHost(tester);
    expect(find.text('HomeScreen'), findsOneWidget);

    container
        .read(inAppNotificationControllerProvider.notifier)
        .enqueue(
          _notification(id: 'n1'),
          presentation: InAppPresentation.banner,
        );
    await tester.pump();

    // The banner is visible...
    expect(find.text('Price drop on Paracetamol'), findsOneWidget);
    // ...and the customer has NOT been navigated anywhere.
    expect(find.text('HomeScreen'), findsOneWidget);
  });

  testWidgets('the banner releases itself without the customer acting', (
    tester,
  ) async {
    final container = await _pumpHost(tester);
    container
        .read(inAppNotificationControllerProvider.notifier)
        .enqueue(
          _notification(id: 'n1'),
          presentation: InAppPresentation.banner,
        );
    await tester.pump();
    expect(find.text('Price drop on Paracetamol'), findsOneWidget);

    // Auto-dismiss after the display window; no lingering clutter.
    await tester.pump(inAppBannerDuration);
    await tester.pumpAndSettle();
    expect(find.text('Price drop on Paracetamol'), findsNothing);
  });

  testWidgets('tapping the banner queues the deep link instead of losing it', (
    tester,
  ) async {
    final container = await _pumpHost(tester);
    container
        .read(inAppNotificationControllerProvider.notifier)
        .enqueue(
          _notification(id: 'n1', targetId: 'prod_77'),
          presentation: InAppPresentation.banner,
        );
    await tester.pump();

    await tester.tap(find.byKey(const Key('inAppNotification_n1')));
    await tester.pumpAndSettle();

    final pending = container.read(pendingDeepLinkControllerProvider);
    expect(pending, isNotNull);
    expect(pending!.path, '/product/prod_77');
    expect(pending.notificationId, 'n1');
    // The banner is gone — the customer acted on it.
    expect(find.text('Price drop on Paracetamol'), findsNothing);
  });

  testWidgets('the dismiss button clears the banner without navigating', (
    tester,
  ) async {
    final container = await _pumpHost(tester);
    container
        .read(inAppNotificationControllerProvider.notifier)
        .enqueue(
          _notification(id: 'n1'),
          presentation: InAppPresentation.banner,
        );
    await tester.pump();

    await tester.tap(find.byKey(const Key('inAppNotificationDismiss')));
    await tester.pumpAndSettle();

    expect(find.text('Price drop on Paracetamol'), findsNothing);
    expect(find.text('HomeScreen'), findsOneWidget);
    expect(container.read(pendingDeepLinkControllerProvider), isNull);
  });

  testWidgets('a burst of messages shows one at a time, never a pile', (
    tester,
  ) async {
    final container = await _pumpHost(tester);
    final controller = container.read(
      inAppNotificationControllerProvider.notifier,
    );
    for (final id in ['n1', 'n2', 'n3']) {
      controller.enqueue(
        _notification(id: id),
        presentation: InAppPresentation.banner,
      );
    }
    await tester.pump();

    // Keyed rather than `find.byType(InkWell)`: the host `Scaffold` contributes
    // its own InkWells, so a type-based finder would count chrome as banners and
    // never actually prove "one at a time".
    expect(find.byKey(const Key('inAppNotification_n1')), findsOneWidget);
    expect(find.byKey(const Key('inAppNotification_n2')), findsNothing);
    expect(find.byKey(const Key('inAppNotification_n3')), findsNothing);
    expect(container.read(inAppNotificationControllerProvider).queue.length, 2);
  });

  testWidgets('an expired link shows a message and navigates nowhere', (
    tester,
  ) async {
    final container = await _pumpHost(tester);
    container
        .read(inAppNotificationControllerProvider.notifier)
        .enqueue(
          AppNotification(
            id: 'n2',
            title: 'Flat 20% off',
            body: 'This offer has ended',
            timestamp: DateTime.now(),
            type: NotificationType.offer,
            deepLink: NotificationDeepLink(
              targetType: DeepLinkTargetType.offer,
              targetId: 'offer_9',
              expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
            ),
          ),
          presentation: InAppPresentation.banner,
        );
    await tester.pump();

    await tester.tap(find.byKey(const Key('inAppNotification_n2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('no longer available'), findsOneWidget);
    expect(container.read(pendingDeepLinkControllerProvider), isNull);
    expect(find.text('HomeScreen'), findsOneWidget);
  });
}
