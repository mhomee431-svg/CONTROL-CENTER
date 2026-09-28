import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hyperlocal_app/core/network/api_error_handler.dart';
import 'package:hyperlocal_app/core/permissions/data/permission_service.dart';
import 'package:hyperlocal_app/core/permissions/permission_models.dart';
import 'package:hyperlocal_app/features/search/data/mock_search_repository.dart';
import 'package:hyperlocal_app/features/search/domain/models/search_models.dart';
import 'package:hyperlocal_app/features/search/domain/search_repository.dart';
import 'package:hyperlocal_app/features/search/presentation/screens/barcode_scan_screen.dart';
import 'package:hyperlocal_app/features/search/presentation/widgets/shop_product_card.dart';

/// A fake that fails the route itself: the backend has no barcode endpoint.
class _MissingRouteRepository implements SearchRepository {
  @override
  Future<List<ShopProductResult>> lookupBarcode(
    String barcode, {
    double? latitude,
    double? longitude,
  }) async {
    throw const ApiException(
      type: ApiErrorType.notFound,
      message: 'The requested resource was not found.',
      statusCode: 404,
    );
  }

  @override
  Future<List<ShopProductResult>> searchProducts({
    required String query,
    required int page,
    required int limit,
    SortOption sort = SortOption.nearest,
    Map<String, dynamic>? filters,
    double? latitude,
    double? longitude,
  }) async =>
      const [];

  @override
  Future<List<String>> getPopularSearches() async => const [];

  @override
  Future<List<String>> getRecentSearches() async => const [];

  @override
  Future<List<SearchSuggestion>> getSuggestions(String query) async =>
      const [];
}

/// A repository whose barcode lookup fails until the test flips [failing].
///
/// Deliberately NOT "fail exactly once": the scan screen can dispatch the
/// lookup more than once for a single detection (gate handshake, rebuild, and
/// the tap itself), so a fixed failure count would make the test depend on
/// internal call sequencing. The test owns the switch instead — the error state
/// is held on screen for as long as it wants, then a retry is allowed to pass.
class _FailOnceRepository implements SearchRepository {
  _FailOnceRepository(this.inner, this.error);

  final SearchRepository inner;
  final Object error;

  /// While true every lookup throws [error]; flip to false to let it through.
  var failing = true;

  /// Total lookups attempted, so a test can assert the retry really re-fetched.
  var attempts = 0;

  @override
  Future<List<ShopProductResult>> lookupBarcode(
    String barcode, {
    double? latitude,
    double? longitude,
  }) async {
    attempts++;
    if (failing) throw error;
    return inner.lookupBarcode(
      barcode,
      latitude: latitude,
      longitude: longitude,
    );
  }

  @override
  Future<List<ShopProductResult>> searchProducts({
    required String query,
    required int page,
    required int limit,
    SortOption sort = SortOption.nearest,
    Map<String, dynamic>? filters,
    double? latitude,
    double? longitude,
  }) =>
      inner.searchProducts(
        query: query,
        page: page,
        limit: limit,
        sort: sort,
        filters: filters,
        latitude: latitude,
        longitude: longitude,
      );

  @override
  Future<List<String>> getPopularSearches() => inner.getPopularSearches();

  @override
  Future<List<String>> getRecentSearches() => inner.getRecentSearches();

  @override
  Future<List<SearchSuggestion>> getSuggestions(String query) =>
      inner.getSuggestions(query);
}

/// A repository with TWO products behind one barcode (inner pack vs outer
/// case sharing a GS1 code) plus a second shop for the first product.
class _MultiProductRepository implements SearchRepository {
  @override
  Future<List<ShopProductResult>> lookupBarcode(
    String barcode, {
    double? latitude,
    double? longitude,
  }) async {
    ShopProductResult hit({
      required String id,
      required String productId,
      required String productName,
      required String shopId,
      required String shopName,
      required double price,
    }) {
      return ShopProductResult(
        id: id,
        productId: productId,
        productName: productName,
        productImageUrl: '',
        shopId: shopId,
        shopName: shopName,
        price: price,
        isAvailable: true,
        distanceInKm: 1.0,
        shopRating: 4.5,
        lastUpdated: DateTime(2026, 1, 1),
        availability: InventoryAvailability.inStock,
        freshness: FreshnessLevel.fresh,
      );
    }

    return [
      hit(
        id: 'sp-multi-1a',
        productId: 'p-multi-1',
        productName: 'Multipack Beans 4x125g',
        shopId: 's1',
        shopName: 'Gupta Electronics',
        price: 240,
      ),
      hit(
        id: 'sp-multi-1b',
        productId: 'p-multi-1',
        productName: 'Multipack Beans 4x125g',
        shopId: 's2',
        shopName: 'Sharma Store',
        price: 235,
      ),
      hit(
        id: 'sp-multi-2',
        productId: 'p-multi-2',
        productName: 'Single Tin Beans 125g',
        shopId: 's1',
        shopName: 'Gupta Electronics',
        price: 65,
      ),
    ];
  }

  @override
  Future<List<ShopProductResult>> searchProducts({
    required String query,
    required int page,
    required int limit,
    SortOption sort = SortOption.nearest,
    Map<String, dynamic>? filters,
    double? latitude,
    double? longitude,
  }) async =>
      const [];

  @override
  Future<List<String>> getPopularSearches() async => const [];

  @override
  Future<List<String>> getRecentSearches() async => const [];

  @override
  Future<List<SearchSuggestion>> getSuggestions(String query) async =>
      const [];
}

/// Pumps the real scan screen with a granted camera and a fake viewfinder.
///
/// The fake viewfinder is a single "detect" button: tapping it reports
/// [barcode] to the screen exactly the way `MobileScanner.onDetect` would — no
/// camera, no platform channels.
Future<void> pumpScanScreen(
  WidgetTester tester, {
  required SearchRepository repository,
  String barcode = '8901234567890',
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        searchRepositoryProvider.overrideWithValue(repository),
        permissionServiceProvider.overrideWithValue(
          InMemoryPermissionService(
            statuses: {PermissionKind.camera: PermissionOutcome.granted},
          ),
        ),
      ],
      child: MaterialApp(
        home: BarcodeScanScreen(
          scannerBuilder: (context, onDetection) => Center(
            child: ElevatedButton(
              key: const Key('fake_detect'),
              onPressed: () => onDetection(barcode),
              child: const Text('fake detect'),
            ),
          ),
        ),
      ),
    ),
  );
  // Yield to the gate's status-then-request handshake.
  await tester.pump();
  await tester.pump();
}

void main() {
  group('BarcodeScanScreen base flow', () {
    testWidgets(
      'a scan lists the same shops as a manual lookup of the same barcode',
      (tester) async {
        await pumpScanScreen(tester, repository: MockSearchRepository());
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('fake_detect')), findsOneWidget);
        await tester.tap(find.byKey(const Key('fake_detect')));
        await tester.pumpAndSettle();

        // Same code, same shops, same card as the manual-entry sheet proves.
        expect(find.text('Gupta Electronics'), findsOneWidget);
        expect(find.text('Bosch Impact Drill 13mm'), findsOneWidget);
        expect(find.byKey(const Key('barcode_results_list')), findsOneWidget);
      },
    );

    testWidgets(
      'an empty lookup reports honestly and offers another scan',
      (tester) async {
        await pumpScanScreen(
          tester,
          repository: MockSearchRepository(),
          barcode: '0000000000000',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('fake_detect')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('barcode_results_empty')), findsOneWidget);
        expect(find.text('Gupta Electronics'), findsNothing);
        // "Scan another" returns to a live viewfinder…
        await tester.tap(find.text('Scan another barcode'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('fake_detect')), findsOneWidget);
      },
    );

    testWidgets(
      'a missing route shows the unavailable copy and hides re-scan',
      (tester) async {
        await pumpScanScreen(tester, repository: _MissingRouteRepository());
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('fake_detect')));
        await tester.pumpAndSettle();

        // The route does not exist here: say so plainly…
        expect(
          find.byKey(const Key('barcode_results_unavailable')),
          findsOneWidget,
        );
        // …and do not offer a scan that cannot work. Manual entry would hit the
        // same missing route, so it is dropped as well.
        expect(find.text('Scan another barcode'), findsNothing);
        expect(find.text('Enter barcode manually'), findsNothing);
      },
    );

    testWidgets(
      'manual entry stays reachable from the AppBar while scanning',
      (tester) async {
        await pumpScanScreen(tester, repository: MockSearchRepository());
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('scan_manual_entry')), findsOneWidget);
      },
    );
  });

  group('BarcodeScanScreen failure and retry', () {
    testWidgets(
      'a transient failure can be retried and then resolves',
      (tester) async {
        final repository = _FailOnceRepository(
          MockSearchRepository(),
          const ApiException(
            type: ApiErrorType.timeout,
            message: 'The lookup timed out.',
          ),
        );
        await pumpScanScreen(tester, repository: repository);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('fake_detect')));
        await tester.pumpAndSettle();

        // The lookup failed, so the error state is shown and no results are
        // claimed. The repository keeps failing until the test allows a retry.
        expect(find.byKey(const Key('barcode_results_error')), findsOneWidget);
        expect(find.byKey(const Key('barcode_results_list')), findsNothing);
        final attemptsBeforeRetry = repository.attempts;
        expect(attemptsBeforeRetry, greaterThan(0));

        // Let the next lookup through and retry the SAME code.
        repository.failing = false;
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();

        // Retry genuinely re-hit the repository…
        expect(repository.attempts, greaterThan(attemptsBeforeRetry));
        // …and the recovered result is rendered, not the error.
        expect(find.byKey(const Key('barcode_results_error')), findsNothing);
        expect(find.byKey(const Key('barcode_results_list')), findsOneWidget);
        expect(find.text('Gupta Electronics'), findsOneWidget);
      },
    );
  });

  group('BarcodeScanScreen multi-match results', () {
    testWidgets(
      'one barcode resolving to several products lists every match',
      (tester) async {
        await pumpScanScreen(tester, repository: _MultiProductRepository());
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('fake_detect')));
        await tester.pumpAndSettle();

        // Two DISTINCT products behind one barcode are grouped so the customer
        // picks WHAT first, then WHERE — not a flat N-shops-x-M-products list.
        expect(find.byKey(const Key('barcode_results_list')), findsNothing);
        expect(find.byKey(const Key('barcode_product_groups')), findsOneWidget);
        expect(
          find.textContaining('2 products share this barcode'),
          findsOneWidget,
        );

        // Both products are offered…
        expect(find.text('Multipack Beans 4x125g'), findsOneWidget);
        expect(find.text('Single Tin Beans 125g'), findsOneWidget);
        // …with the cheapest price and the shop count for that product, so the
        // choice is made on facts (Multipack is stocked by 2 shops).
        expect(find.textContaining('From ₹235 · 2 shops'), findsOneWidget);
        expect(find.textContaining('From ₹65 · 1 shop'), findsOneWidget);

        // Tapping a product opens ITS shops, not a camera restart.
        await tester.tap(find.text('Multipack Beans 4x125g'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('barcode_group_sheet_title')),
          findsOneWidget,
        );
        // Scoped to the sheet: the group list stays mounted underneath it.
        final sheet = find.descendant(
          of: find.byType(DraggableScrollableSheet),
          matching: find.byType(ShopProductCard),
        );
        expect(sheet, findsNWidgets(2));
        expect(
          find.descendant(
            of: find.byType(DraggableScrollableSheet),
            matching: find.text('Gupta Electronics'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(DraggableScrollableSheet),
            matching: find.text('Sharma Store'),
          ),
          findsOneWidget,
        );
        // The OTHER product is not offered in this product's sheet.
        expect(
          find.descendant(
            of: find.byType(DraggableScrollableSheet),
            matching: find.text('Single Tin Beans 125g'),
          ),
          findsNothing,
        );
      },
    );
  });
}
