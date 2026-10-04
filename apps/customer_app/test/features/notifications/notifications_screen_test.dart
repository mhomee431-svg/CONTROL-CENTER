import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal_app/core/router/deep_link.dart';
import 'package:hyperlocal_app/core/router/deep_link_guard.dart';
import 'package:hyperlocal_app/core/router/deep_link_launcher.dart';
import 'package:hyperlocal_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:hyperlocal_app/features/notifications/domain/models/app_notification.dart';
import 'package:hyperlocal_app/features/notifications/domain/models/notification_preferences.dart';
import 'package:hyperlocal_app/features/notifications/domain/notification_repository.dart';
import 'package:hyperlocal_app/features/notifications/presentation/controllers/notifications_controller.dart';
import 'package:hyperlocal_app/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:hyperlocal_app/features/onboarding/presentation/controllers/onboarding_controller.dart';

/// An auth controller pinned to one status, without touching secure storage.
///
/// The real controller reads `flutter_secure_storage` on `build()`, which no
/// widget test should depend on. The deep-link guard reads auth state to decide
/// whether the app is ready to navigate, so the status has to be
/// controllable — but nothing else about auth does.
class _StubAuthController extends AuthController {
  _StubAuthController(this._status);

  final AuthStatus _status;

  @override
  AuthState build() => AuthState(status: _status);
}

/// A probe that answers "it exists" without touching the network.
///
/// `DeepLinkLauncher` verifies that a link's target still exists before
/// navigating. In production that is a real request to the product/shop
/// repositories; in a widget test with a stubbed HTTP client the same request
/// returns 400 and the guard correctly concludes the product is gone — so the
/// screen would never open and the test would be asserting the wrong thing.
class _AlwaysPresentProbe implements DeepLinkTargetProbe {
  @override
  Future<DeepLinkTargetState> probe(DeepLinkIntent intent) async =>
      DeepLinkTargetState.available;
}

/// Onboarding pinned to "finished".
///
/// The real controller reads storage asynchronously on `build()`, which leaves
/// the flag `null` — the "still deciding" state — for the first frame. The
/// deep-link guard treats `null` as not-ready, so without this stub every tap
/// would be refused. A customer who can see the inbox has finished onboarding.
class _StubOnboardingController extends OnboardingCompletedController {
  @override
  bool? build() => true;
}

/// Deterministic repository used by the screen tests.
class _FakeNotificationRepository implements NotificationRepository {
  _FakeNotificationRepository(this.items);

  List<AppNotification> items;

  /// When true every load throws (simulates an unreachable backend).
  bool failAll = false;

  @override
  Future<List<AppNotification>> getNotifications() async {
    if (failAll) throw Exception('simulated failure');
    return List.of(items);
  }

  @override
  Future<void> markAsRead(String id) async {
    items = [
      for (final n in items)
        if (n.id == id && !n.isRead) n.copyWith(isRead: true) else n,
    ];
  }

  @override
  Future<void> markAllAsRead() async {
    items = [for (final n in items) n.copyWith(isRead: true)];
  }

  @override
  Future<NotificationPreferences> getPreferences() async =>
      NotificationPreferences.defaults;

  @override
  Future<void> updatePreferences(NotificationPreferences preferences) async {}

  @override
  Future<void> registerDeviceToken(dynamic registration) async {}

  @override
  Future<void> unregisterDeviceToken(String token) async {}
}

GoRouter _router() {
  return GoRouter(
    initialLocation: '/notifications',
    routes: [
      GoRoute(
        path: '/notifications',
        builder: (_, _) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/product/:id',
        builder: (_, state) =>
            Scaffold(body: Text('ProductPage ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/shop/:id',
        builder: (_, state) =>
            Scaffold(body: Text('ShopPage ${state.pathParameters['id']}')),
      ),
    ],
  );
}

List<AppNotification> _seed() {
  final now = DateTime.now();
  return [
    AppNotification(
      id: 'n1',
      title: 'Price drop alert',
      body: 'Samsung Galaxy S24 is cheaper nearby',
      timestamp: now.subtract(const Duration(hours: 2)),
      type: NotificationType.priceDrop,
      deepLink: const NotificationDeepLink(
        targetType: DeepLinkTargetType.product,
        targetId: 'prod_1',
      ),
    ),
    AppNotification(
      id: 'n2',
      title: 'Shop update',
      body: 'Gupta Electronics has new timings',
      timestamp: now.subtract(const Duration(days: 1)),
      type: NotificationType.shopUpdate,
      deepLink: const NotificationDeepLink(
        targetType: DeepLinkTargetType.shop,
        targetId: 'shop_3',
      ),
    ),
    AppNotification(
      id: 'n3',
      title: 'Expired deal',
      body: 'This offer has already ended',
      timestamp: now.subtract(const Duration(days: 2)),
      type: NotificationType.offer,
      deepLink: NotificationDeepLink(
        targetType: DeepLinkTargetType.offer,
        targetId: 'offer_9',
        expiresAt: now.subtract(const Duration(hours: 1)),
      ),
    ),
    AppNotification(
      id: 'n4',
      title: 'Welcome',
      body: 'No link here',
      timestamp: now,
      type: NotificationType.system,
    ),
  ];
}

void main() {
  Future<void> pumpAndSettleScreen(
    WidgetTester tester,
    _FakeNotificationRepository repository, {
    // Whether the app has finished its launch gates.
    //
    // A notification tap now goes through `DeepLinkLauncher`, which runs the
    // SAME guard an OS deep link does — and that guard refuses while the app is
    // not ready. Leaving these at their defaults (`onboardingCompleted == null`,
    // auth still `initial`) would make the guard refuse every tap, so the test
    // would assert on a fallback screen rather than on the navigation it is
    // named for. Defaults to ready: a customer looking at the inbox has, by
    // definition, already passed onboarding.
    AuthStatus authStatus = AuthStatus.authenticated,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationsRepositoryProvider.overrideWithValue(repository),
          onboardingCompletedProvider.overrideWith(
            () => _StubOnboardingController(),
          ),
          authControllerProvider.overrideWith(
            () => _StubAuthController(authStatus),
          ),
          deepLinkTargetProbeProvider.overrideWithValue(
            _AlwaysPresentProbe(),
          ),
        ],
        child: MaterialApp.router(routerConfig: _router()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a tap before the app is ready falls back, never half-navigates', (
    tester,
  ) async {
    // The counterpart to the guard's readiness rule. While the launch gates are
    // still resolving, a tap must NOT navigate: the router's own redirect would
    // immediately undo it, so the guard sends the customer to its fallback
    // instead. This is the behaviour that stops a tap from being silently lost.
    await pumpAndSettleScreen(
      tester,
      _FakeNotificationRepository(_seed()),
      authStatus: AuthStatus.initial,
    );

    await tester.tap(find.byKey(const Key('notification_n1')));
    await tester.pumpAndSettle();

    expect(
      find.text('ProductPage prod_1'),
      findsNothing,
      reason: 'the router is still gated, so the detail page must not open',
    );
  });

  testWidgets('an empty inbox offers a next action, not just an apology', (
    tester,
  ) async {
    // Spec: every major list's empty state must give the customer something
    // useful to do. An empty inbox with no action is a dead end.
    await pumpAndSettleScreen(tester, _FakeNotificationRepository([]));

    expect(find.text('No notifications yet'), findsOneWidget);
    expect(find.text('Explore shops'), findsOneWidget);
  });

  testWidgets('renders notifications with unread badge and read styling', (
    tester,
  ) async {
    await pumpAndSettleScreen(tester, _FakeNotificationRepository(_seed()));

    expect(find.text('Alerts'), findsOneWidget);
    expect(find.text('Price drop alert'), findsOneWidget);
    // Unread badge shows the 4 unread items.
    expect(find.text('4'), findsOneWidget);

    expect(find.byKey(const Key('markAllReadButton')), findsOneWidget);
    // Read item (none in seed) — verify unread dot exists on unread rows.
    expect(find.byKey(const Key('notification_n1')), findsOneWidget);
  });

  testWidgets('tapping a product notification navigates and marks it read', (
    tester,
  ) async {
    final repository = _FakeNotificationRepository(_seed());
    await pumpAndSettleScreen(tester, repository);

    await tester.tap(find.byKey(const Key('notification_n1')));
    await tester.pumpAndSettle();

    expect(find.text('ProductPage prod_1'), findsOneWidget);
    expect(repository.items.firstWhere((n) => n.id == 'n1').isRead, isTrue);
  });

  testWidgets('expired offer notification degrades safely with a message', (
    tester,
  ) async {
    await pumpAndSettleScreen(tester, _FakeNotificationRepository(_seed()));

    await tester.tap(find.byKey(const Key('notification_n3')));
    await tester.pumpAndSettle();

    // Still on the list — no navigation happened.
    expect(find.text('Alerts'), findsOneWidget);
    expect(find.textContaining('no longer available'), findsOneWidget);
    // But the tap still marks it as read.
    final state = tester.element(find.byKey(const Key('notification_n3')));
    final container = ProviderScope.containerOf(state);
    final items = container.read(notificationsControllerProvider).value ?? [];
    expect(items.firstWhere((n) => n.id == 'n3').isRead, isTrue);
  });

  testWidgets('mark all read clears the badge and hides the action', (
    tester,
  ) async {
    await pumpAndSettleScreen(tester, _FakeNotificationRepository(_seed()));

    await tester.tap(find.byKey(const Key('markAllReadButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('markAllReadButton')), findsNothing);
    expect(find.text('4'), findsNothing);
  });

  testWidgets('shows empty state when there are no notifications', (
    tester,
  ) async {
    await pumpAndSettleScreen(tester, _FakeNotificationRepository([]));

    expect(find.text('No notifications yet'), findsOneWidget);
    expect(find.text('Mark all read'), findsNothing);
  });

  testWidgets('shows error state with working retry', (tester) async {
    final repository = _FakeNotificationRepository(_seed());
    await pumpAndSettleScreen(tester, repository);

    // Backend goes down; the controller's refresh surfaces the failure as
    // an explicit error state (deterministic — not subject to Riverpod's
    // automatic build retries).
    repository.failAll = true;
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NotificationsScreen)),
    );
    await container.read(notificationsControllerProvider.notifier).refresh();
    await tester.pumpAndSettle();

    // Headline is screen-specific copy now ("Unable to load notifications"),
    // matching the shared ErrorState contract rather than one hand-rolled
    // string per screen.
    expect(find.text('Unable to load notifications'), findsOneWidget);
    expect(find.text('Price drop alert'), findsNothing);

    // Backend recovers — the retry button reloads the list.
    repository.failAll = false;
    await tester.tap(find.byKey(const Key('notificationsRetryButton')));
    await tester.pumpAndSettle();

    expect(find.text('Price drop alert'), findsOneWidget);
    expect(find.text('Unable to load notifications'), findsNothing);
  });
}
