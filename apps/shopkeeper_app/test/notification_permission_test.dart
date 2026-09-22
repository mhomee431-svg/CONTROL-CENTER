import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/permissions/data/permission_service.dart';
import 'package:hyperlocal_shopkeeper_app/core/permissions/permission_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/account/presentation/screens/notification_settings_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/notifications/data/notifications_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/notifications/presentation/controllers/notification_permission_controller.dart';

import 'fakes.dart';

/// Device notification permission: the controller that talks to the platform
/// and the *Settings → Notification settings* screen that exposes it.
///
/// The permission NEVER blocks anything — these tests also pin that the screen
/// renders normally in every state, including a refusal.
void main() {
  ProviderContainer containerOf(InMemoryPermissionService permissions) {
    final container = ProviderContainer(overrides: [
      permissionServiceProvider.overrideWithValue(permissions),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  group('NotificationPermissionController', () {
    test('refresh maps every platform outcome, prompting nobody', () async {
      final cases = <PermissionOutcome, NotificationPermissionStatus>{
        PermissionOutcome.granted: NotificationPermissionStatus.granted,
        PermissionOutcome.limited: NotificationPermissionStatus.granted,
        PermissionOutcome.denied: NotificationPermissionStatus.denied,
        PermissionOutcome.permanentlyDenied:
            NotificationPermissionStatus.blocked,
        PermissionOutcome.restricted: NotificationPermissionStatus.blocked,
        PermissionOutcome.unknown: NotificationPermissionStatus.unknown,
      };
      for (final entry in cases.entries) {
        final permissions = InMemoryPermissionService(
          statuses: {PermissionKind.notifications: entry.key},
        );
        final container = containerOf(permissions);
        await container.read(notificationPermissionProvider.notifier).refresh();

        final state = container.read(notificationPermissionProvider);
        expect(state.status, entry.value, reason: '${entry.key}');
        expect(state.isChecking, isFalse, reason: '${entry.key}');
        expect(permissions.requestsFor(PermissionKind.notifications), 0,
            reason: 'refresh reads, it never asks');
      }
    });

    test('enable() asks once and reports the honest outcome', () async {
      final permissions = InMemoryPermissionService(
        requestOutcomes: {PermissionKind.notifications: PermissionOutcome.denied},
      );
      final container = containerOf(permissions);
      final controller = container.read(notificationPermissionProvider.notifier);

      final granted = await controller.enable();
      expect(granted, isFalse);
      expect(permissions.requestsFor(PermissionKind.notifications), 1);
      expect(container.read(notificationPermissionProvider).status,
          NotificationPermissionStatus.denied);
      expect(
        container.read(notificationPermissionProvider).message,
        'Notifications are still switched off. You can turn them on any time '
        'from here.',
      );
    });

    test('a granted enable reports success and settles the status', () async {
      final permissions = InMemoryPermissionService(
        requestOutcomes: {PermissionKind.notifications: PermissionOutcome.granted},
      );
      final container = containerOf(permissions);
      final controller = container.read(notificationPermissionProvider.notifier);

      expect(await controller.enable(), isTrue);
      expect(container.read(notificationPermissionProvider).isGranted, isTrue);
      expect(container.read(notificationPermissionProvider).message,
          'Notifications are allowed on this device.');
    });

    test('a permanent denial routes to the system settings, not a re-ask',
        () async {
      final permissions = InMemoryPermissionService(
        statuses: {PermissionKind.notifications: PermissionOutcome.permanentlyDenied},
      );
      final container = containerOf(permissions);
      final controller = container.read(notificationPermissionProvider.notifier);
      await controller.refresh();
      final state = container.read(notificationPermissionProvider);
      expect(state.needsSettings, isTrue);

      expect(await controller.openSystemSettings(), isTrue);
      expect(permissions.openSettingsCalls, 1);
      // Nothing was asked again — the OS would answer instantly with the same
      // refusal.
      expect(permissions.requestsFor(PermissionKind.notifications), 0);
    });

    test('clearMessage drops the last attempt copy only', () async {
      final permissions = InMemoryPermissionService(
        requestOutcomes: {PermissionKind.notifications: PermissionOutcome.granted},
      );
      final container = containerOf(permissions);
      final controller = container.read(notificationPermissionProvider.notifier);
      await controller.enable();
      expect(container.read(notificationPermissionProvider).message, isNotNull);

      controller.clearMessage();
      expect(container.read(notificationPermissionProvider).message, isNull);
      expect(container.read(notificationPermissionProvider).isGranted, isTrue);
    });
  });

  group('NotificationSettingsScreen (device permission card)', () {
    Future<void> pumpScreen(
      WidgetTester tester,
      InMemoryPermissionService permissions,
    ) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          permissionServiceProvider.overrideWithValue(permissions),
          notificationsRepositoryProvider
              .overrideWithValue(FakeNotificationsRepo()),
        ],
        child: const MaterialApp(home: NotificationSettingsScreen()),
      ));
      // initState post-frame callback reads the platform status.
      await tester.pumpAndSettle();
    }

    testWidgets('a refusal shows Enable Notifications — and nothing blocks',
        (tester) async {
      final permissions = InMemoryPermissionService(
        statuses: {PermissionKind.notifications: PermissionOutcome.denied},
      );
      await pumpScreen(tester, permissions);

      expect(find.text('Not allowed'), findsOneWidget);
      expect(find.text('Enable Notifications'), findsOneWidget);
      expect(find.text('Open System Settings'), findsNothing);

      // The contract: a refusal never blocks the app (the notice sits at the
      // bottom of the long list, so scroll to it).
      await tester.scrollUntilVisible(
        find.textContaining('never block the app'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('never block the app'), findsOneWidget);
    });

    testWidgets('tapping Enable Notifications asks and updates the status',
        (tester) async {
      final permissions = InMemoryPermissionService(
        statuses: {PermissionKind.notifications: PermissionOutcome.denied},
        requestOutcomes: {PermissionKind.notifications: PermissionOutcome.granted},
      );
      await pumpScreen(tester, permissions);

      await tester.tap(find.byKey(const Key('notification_enable_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(permissions.requestsFor(PermissionKind.notifications), 1);
      expect(find.text('Allowed'), findsOneWidget);
      expect(find.byKey(const Key('notification_enable_button')), findsNothing);
      expect(find.text('Notifications are allowed on this device.'),
          findsOneWidget);

      // Let the snackbar timer finish so no timer outlives the test.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('a blocked permission offers the system settings route',
        (tester) async {
      final permissions = InMemoryPermissionService(
        statuses: {PermissionKind.notifications: PermissionOutcome.permanentlyDenied},
      );
      await pumpScreen(tester, permissions);

      expect(find.text('Blocked'), findsOneWidget);
      expect(find.text('Enable Notifications'), findsOneWidget);
      expect(
          find.byKey(const Key('notification_open_settings_button')),
          findsOneWidget);
      expect(find.textContaining('will not ask again'), findsOneWidget);

      await tester.tap(
          find.byKey(const Key('notification_open_settings_button')));
      await tester.pump();
      expect(permissions.openSettingsCalls, 1);
    });

    testWidgets('granted shows the status and keeps the screen usable',
        (tester) async {
      final permissions = InMemoryPermissionService(
        statuses: {PermissionKind.notifications: PermissionOutcome.granted},
      );
      await pumpScreen(tester, permissions);

      expect(find.text('Allowed'), findsOneWidget);
      expect(find.byKey(const Key('notification_enable_button')), findsNothing);

      await tester.scrollUntilVisible(
        find.textContaining('never block the app'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('never block the app'), findsOneWidget);
    });
  });
}
