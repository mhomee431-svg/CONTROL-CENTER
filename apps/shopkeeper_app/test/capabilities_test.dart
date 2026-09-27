import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_providers.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/core/ui/capability_gate.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/dashboard/domain/dashboard_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/shell/capabilities_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/shell/all_features_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/domain/shop_models.dart';

import 'fakes.dart';

/// The permissive legacy set — what a shop that predates monetization (or a
/// backend that sends no capabilities block) must keep seeing.
const allOn = ShopCapabilities();

/// A Basic-plan payload: every paid feature is off.
const allOff = ShopCapabilities(
  canUsePos: false,
  canUploadExcel: false,
  canCreateOffers: false,
  canViewReports: false,
);

/// Overrides the centralized layer with fixed flags (no network).
class _FixedCapabilities extends CapabilitiesController {
  _FixedCapabilities(this.flags);
  final ShopCapabilities flags;

  @override
  ShopCapabilities build() => flags;
}

/// Wraps [child] in a scope whose centralized capability layer is fixed at
/// [caps] — no network, deterministic gating.
///
/// The key matters: `ProviderScope` builds its container in `initState`, so
/// re-pumping the SAME scope tree would keep the first container (and its
/// first override). Keying on the flags forces a fresh container whenever the
/// capability set changes.
Widget capsScope(ShopCapabilities caps, Widget child) => ProviderScope(
      key: ValueKey('caps:${caps.toJson()}'),
      overrides: [
        capabilitiesControllerProvider.overrideWith(() => _FixedCapabilities(caps)),
      ],
      child: child,
    );

/// ── 1. JSON contract ────────────────────────────────────────────────────────

void main() {
  group('ShopCapabilities.fromJson', () {
    test('reads the exact keys the backend publishes', () {
      final caps = ShopCapabilities.fromJson({
        'canUsePos': false,
        'canUploadExcel': true,
        'canCreateOffers': false,
        'canViewReports': true,
      });

      expect(caps.canUsePos, isFalse);
      expect(caps.canUploadExcel, isTrue);
      expect(caps.canCreateOffers, isFalse);
      expect(caps.canViewReports, isTrue);
    });

    test('an absent capabilities block stays PERMISSIVE', () {
      // An old backend (or a cached payload) must never lock a shopkeeper out
      // of their own screens.
      final caps = ShopCapabilities.fromJson(null);

      expect(caps.canUsePos, isTrue);
      expect(caps.canUploadExcel, isTrue);
      expect(caps.canCreateOffers, isTrue);
      expect(caps.canViewReports, isTrue);
    });

    test('a partial block only downgrades the keys it names', () {
      final caps = ShopCapabilities.fromJson({'canUsePos': false});

      expect(caps.canUsePos, isFalse);
      expect(caps.canUploadExcel, isTrue);
      expect(caps.canCreateOffers, isTrue);
      expect(caps.canViewReports, isTrue);
    });

    test('toJson round-trips through fromJson', () {
      expect(ShopCapabilities.fromJson(allOff.toJson()).canUsePos, isFalse);
      expect(ShopCapabilities.fromJson(allOn.toJson()).canUsePos, isTrue);
    });
  });

  group('ShopCapabilities in the dashboard payload', () {
    test('parses the capabilities block the backend piggybacks', () {
      final data = DashboardData.fromJson({
        'products': {'total': 3},
        'capabilities': {
          'canUsePos': false,
          'canUploadExcel': true,
          'canCreateOffers': false,
          'canViewReports': true,
        },
      });

      expect(data.capabilities.canUsePos, isFalse);
      expect(data.capabilities.canUploadExcel, isTrue);
      expect(data.capabilities.canCreateOffers, isFalse);
      expect(data.capabilities.canViewReports, isTrue);
    });

    test('an old dashboard payload without the block is permissive', () {
      final data = DashboardData.fromJson({'products': {'total': 0}});

      expect(data.capabilities.canUsePos, isTrue);
      expect(data.capabilities.canViewReports, isTrue);
    });
  });


  // ── 2. The controller ──────────────────────────────────────────────────────

  group('CapabilitiesController', () {
    ProviderContainer makeContainer({
      Map<String, dynamic>? payload,
      Object? error,
      int? shopId = 10,
      String? accessToken = 'test-access-token',
    }) {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = _StubAdapter(payload: payload, error: error);
      addTearDown(dio.close);
      final container = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(ApiClient(dio: dio)),
        tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: accessToken)),
        selectedShopProvider.overrideWith(
            () => SelectedShopOverride(shopId == null ? null : ownerShop(id: shopId))),
      ]);
      addTearDown(container.dispose);
      return container;
    }

    test('starts PERMISSIVE so nothing is hidden before the first load', () {
      final container = makeContainer();

      final caps = container.read(capabilitiesControllerProvider);

      expect(caps.canUsePos, isTrue);
      expect(caps.canUploadExcel, isTrue);
      expect(caps.canCreateOffers, isTrue);
      expect(caps.canViewReports, isTrue);
    });

    test('load() publishes the backend flags verbatim', () async {
      final container = makeContainer(payload: allOff.toJson());

      await container
          .read(capabilitiesControllerProvider.notifier)
          .load(10, 'test-access-token');

      final caps = container.read(capabilitiesControllerProvider);
      expect(caps.canUsePos, isFalse);
      expect(caps.canUploadExcel, isFalse);
      expect(caps.canCreateOffers, isFalse);
      expect(caps.canViewReports, isFalse);
    });

    test('load() is fail-soft: a network error keeps the current flags', () async {
      final container = makeContainer(error: 'offline');
      container.read(capabilitiesControllerProvider.notifier).adopt(allOff);

      await container
          .read(capabilitiesControllerProvider.notifier)
          .load(10, 'test-access-token');

      // The previous flags survive rather than snapping to the permissive
      // default, so a flaky request never un-gates a locked feature.
      expect(container.read(capabilitiesControllerProvider).canUsePos, isFalse);
    });

    test('adopt() takes flags already embedded in another payload', () {
      final container = makeContainer();

      container.read(capabilitiesControllerProvider.notifier).adopt(allOff);

      expect(container.read(capabilitiesControllerProvider).canUsePos, isFalse);
    });

    test('reset() restores the permissive set (logout)', () {
      final container = makeContainer();
      final notifier = container.read(capabilitiesControllerProvider.notifier)
        ..adopt(allOff);

      notifier.reset();

      expect(container.read(capabilitiesControllerProvider).canUsePos, isTrue);
    });

    test('loadForSelectedShop() asks the backend for the selected shop',
        () async {
      final adapter = _StubAdapter(payload: allOff.toJson());
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = adapter;
      addTearDown(dio.close);
      final container = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(ApiClient(dio: dio)),
        tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token')),
        selectedShopProvider.overrideWith(() => SelectedShopOverride(ownerShop(id: 77))),
      ]);
      addTearDown(container.dispose);

      await container
          .read(capabilitiesControllerProvider.notifier)
          .loadForSelectedShop();

      expect(adapter.requestedPaths.single, contains('/shops/77/capabilities'));
      expect(container.read(capabilitiesControllerProvider).canUsePos, isFalse);
    });

    test('loadForSelectedShop() is a no-op with no shop selected', () async {
      final adapter = _StubAdapter(payload: allOff.toJson());
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = adapter;
      addTearDown(dio.close);
      final container = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(ApiClient(dio: dio)),
        tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token')),
        selectedShopProvider.overrideWith(() => SelectedShopOverride(null)),
      ]);
      addTearDown(container.dispose);

      await container
          .read(capabilitiesControllerProvider.notifier)
          .loadForSelectedShop();

      // No shop means nothing to be entitled to; guessing would leak one
      // shop's flags onto another.
      expect(adapter.requestedPaths, isEmpty);
    });
  });


  // ── 3. The gate widget ─────────────────────────────────────────────────────

  group('CapabilityGate', () {
    Widget wrap(ShopCapabilities caps, Widget child) => capsScope(
          caps,
          MaterialApp(
            home: Scaffold(
              body: CapabilityGate(
                allowed: caps.canUsePos,
                title: 'POS not available on your plan',
                message: 'Upgrade to connect a point of sale.',
                child: child,
              ),
            ),
          ),
        );

    testWidgets('allowed: renders the real feature, no locked copy',
        (tester) async {
      await tester.pumpWidget(wrap(allOn, const Text('POS body')));

      expect(find.text('POS body'), findsOneWidget);
      expect(find.byKey(const Key('capability-locked')), findsNothing);
      expect(find.text('POS not available on your plan'), findsNothing);
    });

    testWidgets('denied: hides the feature and shows the upgrade copy',
        (tester) async {
      await tester.pumpWidget(wrap(allOff, const Text('POS body')));

      expect(find.text('POS body'), findsNothing);
      expect(find.byKey(const Key('capability-locked')), findsOneWidget);
      expect(find.text('POS not available on your plan'), findsOneWidget);
      expect(find.text('Upgrade to connect a point of sale.'), findsOneWidget);
    });

    testWidgets('the gate swaps locked <-> content when flags change',
        (tester) async {
      // A screen watching the provider must react the moment the backend
      // publishes new flags (e.g. right after an upgrade).
      final container = ProviderContainer(
        overrides: [
          capabilitiesControllerProvider.overrideWith(
            () => _FixedCapabilities(allOff),
          ),
        ],
      );

      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  final caps = ref.watch(capabilitiesControllerProvider);
                  return CapabilityGate(
                    allowed: caps.canUsePos,
                    title: 'locked',
                    message: 'upgrade',
                    child: const Text('POS body'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('POS body'), findsNothing);
      expect(find.text('locked'), findsOneWidget);

      container.read(capabilitiesControllerProvider.notifier).adopt(allOn);
      await tester.pumpAndSettle();

      expect(find.text('POS body'), findsOneWidget);
      expect(find.text('locked'), findsNothing);
    });
  });


  // ── 4. The feature hub gates off the SAME source ───────────────────────────

  group('AllFeaturesScreen', () {
    Future<void> pumpHub(WidgetTester tester, ShopCapabilities caps) =>
        tester.pumpWidget(
          capsScope(caps, const MaterialApp(home: AllFeaturesScreen())),
        );

    testWidgets('a full plan sees every feature tile', (tester) async {
      await pumpHub(tester, allOn);

      expect(find.byKey(const Key('feature-tile-pos')), findsOneWidget);
      expect(find.byKey(const Key('feature-tile-imports')), findsOneWidget);
      expect(find.byKey(const Key('feature-tile-import-center')), findsOneWidget);
      expect(find.byKey(const Key('feature-tile-offers')), findsOneWidget);
      expect(find.byKey(const Key('feature-tile-insights')), findsOneWidget);
    });

    testWidgets('each flag hides exactly its own tile', (tester) async {
      // One flag off at a time proves the tiles are wired to the matching
      // backend flag rather than to one blanket switch.
      final cases = <String, ShopCapabilities>{
        'feature-tile-pos': const ShopCapabilities(canUsePos: false),
        'feature-tile-imports': const ShopCapabilities(canUploadExcel: false),
        'feature-tile-import-center':
            const ShopCapabilities(canUploadExcel: false),
        'feature-tile-offers': const ShopCapabilities(canCreateOffers: false),
        'feature-tile-insights': const ShopCapabilities(canViewReports: false),
      };

      for (final entry in cases.entries) {
        await pumpHub(tester, entry.value);
        expect(find.byKey(Key(entry.key)), findsNothing,
            reason: '${entry.key} must hide when its flag is false');
        // Ungated tiles never disappear.
        expect(find.byKey(const Key('feature-tile-dashboard')), findsOneWidget);
        expect(find.byKey(const Key('feature-tile-products')), findsOneWidget);
        expect(find.byKey(const Key('feature-tile-inventory')), findsOneWidget);
      }
    });

    testWidgets('a basic plan keeps the ungated business tiles', (tester) async {
      await pumpHub(tester, allOff);

      expect(find.byKey(const Key('feature-tile-pos')), findsNothing);
      expect(find.byKey(const Key('feature-tile-offers')), findsNothing);
      expect(find.byKey(const Key('feature-tile-insights')), findsNothing);
      expect(find.byKey(const Key('feature-tile-dashboard')), findsOneWidget);
      expect(find.byKey(const Key('feature-tile-products')), findsOneWidget);
      expect(find.byKey(const Key('feature-tile-inventory')), findsOneWidget);
      expect(find.byKey(const Key('feature-tile-shop-profile')), findsOneWidget);
      expect(find.byKey(const Key('feature-tile-settings')), findsOneWidget);
    });
  });
}

/// Dio adapter that answers every request with a fixed capabilities payload
/// (or a failure), and records the paths it was asked for.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({this.payload, this.error});

  final Map<String, dynamic>? payload;
  final Object? error;
  final List<String> requestedPaths = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedPaths.add(options.path);
    if (error != null) {
      return ResponseBody.fromString(
        '{"message":"offline"}',
        503,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode({'success': true, 'message': 'Success', 'data': payload}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

