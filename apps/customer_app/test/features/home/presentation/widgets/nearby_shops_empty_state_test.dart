import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal_app/features/home/domain/home_repository.dart';
import 'package:hyperlocal_app/features/home/domain/models/home_data.dart';
import 'package:hyperlocal_app/features/home/presentation/controllers/home_controller.dart';
import 'package:hyperlocal_app/features/home/presentation/widgets/nearby_shops_section.dart';

/// Records the radius every home-feed read actually asked the backend for, and
/// always returns an empty nearby list so the empty state stays on screen
/// after each widen (a realistic "still empty after widening" scenario).
class _RecordingHomeRepository implements HomeRepository {
  final List<double?> radiusLog = <double?>[];

  @override
  Future<HomeData> fetchHomeFeed({
    double? latitude,
    double? longitude,
    double? radiusKm,
  }) async {
    radiusLog.add(radiusKm);
    return const HomeData(
      categories: [],
      popularProducts: [],
      nearbyShops: [],
      recentSearches: [],
    );
  }

  @override
  Future<ShopsByPinPage> fetchShopsByPincode(
    String pincode, {
    int page = 1,
    required int limit,
  }) async => ShopsByPinPage.empty;
}

/// Renders the real feed (so a widening actually re-reads) and hands the
/// resulting nearby list to the widget under test.
class _HomeHost extends ConsumerWidget {
  const _HomeHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(homeControllerProvider);
    return feed.when(
      data: (data) => NearbyShopsSection(shops: data.nearbyShops),
      loading: () => const Center(child: Text('loading')),
      error: (_, _) => const Center(child: Text('feed-error')),
    );
  }
}

GoRouter _router() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => const Scaffold(
        // Bounded: the empty state owns a SingleChildScrollView, which needs a
        // finite height or the test renders itself with an infinite viewport.
        body: SizedBox(height: 800, child: _HomeHost()),
      ),
    ),
    GoRoute(
      path: '/select-location',
      builder: (_, _) =>
          const Scaffold(body: Center(child: Text('SelectLocationPage'))),
    ),
    GoRoute(
      path: '/search-results-by-pin/:pin',
      builder: (_, state) => Scaffold(
        body: Center(child: Text('Pin:${state.pathParameters['pin']}')),
      ),
    ),
  ],
);

Future<_RecordingHomeRepository> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final repository = _RecordingHomeRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [homeRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp.router(routerConfig: _router()),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  testWidgets(
    'a no-result nearby section offers exactly the supported recoveries',
    (tester) async {
      await _pump(tester);

      expect(find.text('No nearby shops found'), findsOneWidget);
      // The first read used the BACKEND default, not a radius the UI invented.
      expect(
        find.byKey(const Key('nearbySearchWider')),
        findsOneWidget,
        reason: 'increase radius must be offered while a wider step exists',
      );
      expect(find.byKey(const Key('nearbyChangeLocation')), findsOneWidget);
      expect(find.byKey(const Key('nearbySearchAnotherArea')), findsOneWidget);
      // The label says what leaves the device rather than "search wider".
      expect(find.text('Search within 10 km'), findsOneWidget);
    },
  );

  testWidgets('increase radius re-reads the feed and names the next step', (
    tester,
  ) async {
    final repository = await _pump(tester);
    expect(repository.radiusLog, [null]);

    await tester.tap(find.byKey(const Key('nearbySearchWider')));
    await tester.pumpAndSettle();

    // A REAL query with a wider radius — not a client-side filter over a list
    // that is already empty.
    expect(repository.radiusLog, [null, 10]);
    expect(find.text('Search within 25 km'), findsOneWidget);
  });

  testWidgets('the increase-radius action stops at the backend maximum', (
    tester,
  ) async {
    final repository = await _pump(tester);

    // 10 → 25 → 50 → 100, then nothing: 100 is the server's `le=100`.
    for (final expected in ['10', '25', '50', '100']) {
      expect(
        find.text('Search within $expected km'),
        findsOneWidget,
        reason: 'next step after $expected must be named',
      );
      await tester.tap(find.byKey(const Key('nearbySearchWider')));
      await tester.pumpAndSettle();
    }

    expect(repository.radiusLog, [null, 10, 25, 50, 100]);
    // Exhausted: the button is gone rather than left there to do nothing.
    expect(find.byKey(const Key('nearbySearchWider')), findsNothing);
  });

  testWidgets('change location opens the location picker', (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('nearbyChangeLocation')));
    await tester.pumpAndSettle();

    expect(find.text('SelectLocationPage'), findsOneWidget);
  });

  testWidgets('search another area asks for a pin and opens that area', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('nearbySearchAnotherArea')));
    await tester.pumpAndSettle();
    expect(find.text('Enter Area Pin Code'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '123456');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('areaPinCheck')));
    await tester.pumpAndSettle();

    expect(find.text('Pin:123456'), findsOneWidget);
  });

  testWidgets('a pin that is not six digits never leaves the dialog', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('nearbySearchAnotherArea')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '12ab');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('areaPinCheck')));
    await tester.pumpAndSettle();

    // Still on the dialog, and no request for a malformed pin was made.
    expect(find.text('Enter Area Pin Code'), findsOneWidget);
    expect(find.text('Pin:12ab'), findsNothing);
  });
}
