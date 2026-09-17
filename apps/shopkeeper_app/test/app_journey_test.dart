import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/app.dart';
import 'package:hyperlocal_shopkeeper_app/core/auth/firebase_auth_service.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/data/auth_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/domain/auth_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/dashboard/data/dashboard_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/insights/data/insights_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/insights/domain/insights_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/insights/presentation/controllers/insights_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/shell/all_features_screen.dart';

import 'fakes.dart';

/// The journey's "Main Shopkeeper Features" block requires every one of these
/// DESTINATIONS to be reachable from Shopkeeper Home.
///
/// Inventory has its own destination and Imports / POS is split across three
/// screens (the Excel import, the guided Import Center and POS), so the feature
/// map carries 12 tiles for the 10 journey features. Dashboard is the shell root
/// (bottom nav) and is asserted separately.
const List<String> kJourneyFeatureRoutes = <String>[
  '/products',
  '/offers',
  '/inventory-import',
  '/pos',
  '/insights',
  '/shop-profile',
  '/notifications',
  '/shop-settings',
  '/support',
];

ShopSummary? _shopOf(AuthSession? session) {
  if (session == null || session.shops.isEmpty) return null;
  return session.shops.first;
}

/// App container with the dashboard + insights backends faked.
ProviderContainer journeyContainer({
  AuthSession? session,
  FakeInsightsRepo? insights,
}) {
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository()..restoreResult = session,
      ),
      dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepo()),
      insightsRepositoryProvider.overrideWithValue(
        insights ?? FakeInsightsRepo(),
      ),
      tokenStoreProvider.overrideWithValue(
        InMemoryTokenStore(accessToken: 'test-access-token'),
      ),
      firebaseAuthServiceProvider.overrideWithValue(FakeFirebaseAuthService()),
      selectedShopProvider.overrideWith(
        () => SelectedShopOverride(_shopOf(session)),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> pumpJourneyApp(
  WidgetTester tester,
  ProviderContainer container,
) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const ShopkeeperApp(),
    ),
  );
  await tester.pumpAndSettle();
}

/// Scrolls a hub tile into view and taps it.
Future<void> tapFeatureTile(WidgetTester tester, String id) async {
  final finder = find.byKey(Key('feature-tile-$id'));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('Journey 1 — gate chain (splash → auth → profile check)', () {
    testWidgets('signed out -> Welcome (splash never blocks)', (tester) async {
      await pumpJourneyApp(tester, journeyContainer());
      expect(find.text('Welcome Back'), findsOneWidget);
      expect(find.text('Quick Actions'), findsNothing);
    });

    testWidgets(
      'signed in without a shop -> Create Shopkeeper Profile (profile check)',
      (tester) async {
        await pumpJourneyApp(
          tester,
          journeyContainer(session: makeEmptyProfileSession()),
        );
        expect(find.text('Create Your Shopkeeper Profile'), findsOneWidget);
        expect(find.text('Quick Actions'), findsNothing);
      },
    );

    testWidgets('signed in with a shop -> Shopkeeper Home', (tester) async {
      await pumpJourneyApp(tester, journeyContainer(session: makeSession()));
      expect(find.text('Kirana Corner'), findsOneWidget);
      expect(find.text('Quick Actions'), findsOneWidget);
      expect(find.text('Create Your Shopkeeper Profile'), findsNothing);
    });

    testWidgets('restricted account is gated out of the app', (tester) async {
      await pumpJourneyApp(
        tester,
        journeyContainer(session: makeRestrictedSession()),
      );
      // The account-status gate owns the screen: Home is unreachable.
      expect(find.text('Quick Actions'), findsNothing);
      expect(find.text('Sign out'), findsOneWidget);
    });
  });

  group('Journey 2 — main features are all reachable', () {
    test('the feature map covers every journey destination', () {
      final routes = kShopkeeperFeatures
          .map((feature) => feature.route)
          .toSet();
      for (final route in kJourneyFeatureRoutes) {
        expect(
          routes,
          contains(route),
          reason: '$route is missing from the feature map',
        );
      }
      // Dashboard is the shell root — always reachable via the bottom nav.
      expect(routes, contains('/dashboard'));
      // Tile keys are stable and unique.
      final ids = kShopkeeperFeatures.map((feature) => feature.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    testWidgets('Home exposes the journey quick actions', (tester) async {
      await pumpJourneyApp(tester, journeyContainer(session: makeSession()));
      expect(find.text('Quick Actions'), findsOneWidget);
      for (final label in const [
        'Add Product',
        'Inventory',
        'Pricing & Offers',
        'Reports & Insights',
        'Shop Profile',
        'All Features',
      ]) {
        expect(find.text(label), findsOneWidget, reason: '$label missing');
      }
    });

    testWidgets('Home -> All features lists every journey feature', (
      tester,
    ) async {
      await pumpJourneyApp(tester, journeyContainer(session: makeSession()));
      await tester.tap(find.text('All Features'));
      await tester.pumpAndSettle();

      expect(find.text('All features'), findsOneWidget);
      for (final feature in kShopkeeperFeatures) {
        expect(
          find.byKey(feature.tileKey),
          findsOneWidget,
          reason: '${feature.title} tile missing',
        );
      }
    });

    testWidgets('Pricing & Offers opens the offers screen', (tester) async {
      await pumpJourneyApp(tester, journeyContainer(session: makeSession()));
      await tester.tap(find.text('Pricing & Offers'));
      await tester.pumpAndSettle();
      expect(find.text('Offers & pricing'), findsOneWidget);
    });

    testWidgets('Reports / Insights opens the report screen', (tester) async {
      await pumpJourneyApp(tester, journeyContainer(session: makeSession()));
      await tester.tap(find.text('Reports & Insights'));
      await tester.pumpAndSettle();

      expect(find.text('Reports & insights'), findsOneWidget);
      // Real backend values are rendered — never placeholder numbers.
      expect(find.text('Views today'), findsOneWidget);
      expect(find.text('42'), findsWidgets);
      expect(find.text('+40.0%'), findsOneWidget);
    });

    testWidgets('imports, POS and support are reachable from the hub', (
      tester,
    ) async {
      await pumpJourneyApp(tester, journeyContainer(session: makeSession()));
      await tester.tap(find.text('All Features'));
      await tester.pumpAndSettle();

      await tapFeatureTile(tester, 'pos');
      expect(find.text('POS integration'), findsWidgets);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tapFeatureTile(tester, 'support');
      expect(find.text('Help & support'), findsWidgets);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tapFeatureTile(tester, 'imports');
      expect(find.text('Import from Excel'), findsWidgets);
    });

    testWidgets('Settings is reachable from the hub', (tester) async {
      await pumpJourneyApp(tester, journeyContainer(session: makeSession()));
      await tester.tap(find.text('All Features'));
      await tester.pumpAndSettle();

      await tapFeatureTile(tester, 'settings');
      expect(find.text('Shop settings'), findsWidgets);
    });
  });

  group('Journey 3 — Reports / Insights data layer', () {
    test('loads and parses the full analytics report for the shop', () async {
      final fake = FakeInsightsRepo();
      final container = journeyContainer(
        session: makeSession(),
        insights: fake,
      );

      await container.read(insightsControllerProvider.notifier).load();

      final state = container.read(insightsControllerProvider);
      expect(state.status, InsightsStatus.ready);
      expect(state.rangeDays, kInsightsDefaultRange);
      expect(fake.calls, 1);
      expect(fake.lastShopId, 10);
      expect(fake.lastDays, kInsightsDefaultRange);

      final bundle = state.bundle!;
      expect(bundle.hasActivity, isTrue);
      expect(bundle.overview.views.today, 42);
      expect(bundle.overview.views.changeLabel, '+40.0%');
      expect(bundle.overview.views.weekChangeLabel, '+16.7%');
      expect(bundle.viewSeries, hasLength(2));
      expect(bundle.viewSeries.last.value, 42);
      expect(bundle.clickSeries.last.value, 12);
      expect(bundle.topProducts.first.label, 'SKU-RICE-1');
      // A product without a SKU falls back to its id — never an invented name.
      expect(bundle.topProducts.last.label, 'Product #8');
      expect(bundle.topSearches.first.query, 'basmati rice');
      expect(bundle.interactions.total, 6);
      expect(bundle.devices.total, 42);
      expect(bundle.devices.shares.first.label, 'Android');
      expect(bundle.devices.shares.first.shareLabel, '71.4%');
      expect(bundle.peakHour!.label, '18:00');
      expect(bundle.freshness.scoreLabel, '75%');
      expect(bundle.freshness.scoreFraction, 0.75);
    });

    test('changing the window refetches for the new range', () async {
      final fake = FakeInsightsRepo();
      final container = journeyContainer(
        session: makeSession(),
        insights: fake,
      );
      await container.read(insightsControllerProvider.notifier).load();
      await container.read(insightsControllerProvider.notifier).setRange(7);

      final state = container.read(insightsControllerProvider);
      expect(state.status, InsightsStatus.ready);
      expect(state.rangeDays, 7);
      expect(fake.lastDays, 7);
      expect(fake.calls, 2);
    });

    test(
      'backend 403 becomes access-denied (no dashboard:read grant)',
      () async {
        final container = journeyContainer(
          session: makeSession(),
          insights: FakeInsightsRepo(
            error: const ApiException(
              statusCode: 403,
              message: 'You do not have access to this shop.',
            ),
          ),
        );
        await container.read(insightsControllerProvider.notifier).load();

        final state = container.read(insightsControllerProvider);
        expect(state.status, InsightsStatus.accessDenied);
        expect(state.message, 'You do not have access to this shop.');
      },
    );

    test(
      'a network failure becomes an error state, not fake numbers',
      () async {
        final container = journeyContainer(
          session: makeSession(),
          insights: FakeInsightsRepo(error: Exception('boom')),
        );
        await container.read(insightsControllerProvider.notifier).load();

        final state = container.read(insightsControllerProvider);
        expect(state.status, InsightsStatus.error);
        expect(state.bundle, isNull);
      },
    );

    test('no selected shop reports noShop instead of an empty chart', () async {
      final container = journeyContainer(session: makeEmptyProfileSession());
      await container.read(insightsControllerProvider.notifier).load();
      expect(
        container.read(insightsControllerProvider).status,
        InsightsStatus.noShop,
      );
    });

    test('reset clears cached report data', () async {
      final container = journeyContainer(session: makeSession());
      await container.read(insightsControllerProvider.notifier).load();
      expect(container.read(insightsControllerProvider).isReady, isTrue);

      container.read(insightsControllerProvider.notifier).reset();
      final state = container.read(insightsControllerProvider);
      expect(state.status, InsightsStatus.loading);
      expect(state.bundle, isNull);
    });

    testWidgets('a shop with no activity shows the honest empty state', (
      tester,
    ) async {
      final container = journeyContainer(
        session: makeSession(),
        insights: FakeInsightsRepo(json: insightsJson(empty: true)),
      );
      await pumpJourneyApp(tester, container);
      await tester.tap(find.text('Reports & Insights'));
      await tester.pumpAndSettle();

      expect(find.text('No customer activity yet'), findsOneWidget);
      expect(find.text('Views today'), findsNothing);
      expect(find.text('Inventory freshness'), findsOneWidget);
    });

    testWidgets('a failed load shows the retry state', (tester) async {
      final container = journeyContainer(
        session: makeSession(),
        insights: FakeInsightsRepo(error: Exception('boom')),
      );
      await pumpJourneyApp(tester, container);
      await tester.tap(find.text('Reports & Insights'));
      await tester.pumpAndSettle();

      expect(find.text('Could not load reports'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}
