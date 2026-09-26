import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/features/search/domain/models/search_models.dart';

/// Fixed "now" so every expectation below is deterministic.
final DateTime kNow = DateTime(2026, 3, 15, 14, 30);

void main() {
  group('formatFreshnessText — required label set', () {
    test('reports minutes for a sub-hour-old reading', () {
      expect(
        formatFreshnessText(kNow.subtract(const Duration(minutes: 5)), now: kNow),
        'Updated 5 min ago',
      );
      expect(
        formatFreshnessText(kNow.subtract(const Duration(minutes: 42)), now: kNow),
        'Updated 42 min ago',
      );
    });

    test('reports "Updated today" for an earlier reading on the same day', () {
      // 3:30am, same calendar day as kNow (2:30pm).
      expect(
        formatFreshnessText(DateTime(2026, 3, 15, 3, 30), now: kNow),
        'Updated today',
      );
    });

    test('reports "Updated yesterday" for the previous calendar day', () {
      expect(
        formatFreshnessText(DateTime(2026, 3, 14, 23, 59), now: kNow),
        'Updated yesterday',
      );
    });

    test('reports "Stale" beyond yesterday', () {
      expect(
        formatFreshnessText(DateTime(2026, 3, 13, 9, 0), now: kNow),
        'Stale',
      );
    });

    test('reports "Unknown" when the backend supplied no timestamp', () {
      expect(formatFreshnessText(null, now: kNow), 'Unknown');
    });

    test('a reading from seconds ago is "just now", never a fake "5 min"', () {
      expect(
        formatFreshnessText(kNow.subtract(const Duration(seconds: 20)), now: kNow),
        'Updated just now',
      );
      // The boundary: 59s is still "just now", 60s becomes 1 min.
      expect(
        formatFreshnessText(kNow.subtract(const Duration(seconds: 59)), now: kNow),
        'Updated just now',
      );
      expect(
        formatFreshnessText(kNow.subtract(const Duration(seconds: 60)), now: kNow),
        'Updated 1 min ago',
      );
    });
  });

  group('formatFreshnessText — never fabricates a reading', () {
    test('a 0-minute-old reading is not inflated to "5 min ago"', () {
      // Regression: the previous implementation mapped any value <= 1 minute
      // to a hardcoded "5 min ago", inventing time that never elapsed.
      final label = formatFreshnessText(kNow, now: kNow);
      expect(label, 'Updated just now');
      expect(label, isNot(contains('5 min')));
    });

    test('an exactly-1-minute-old reading stays at 1 min, not 5', () {
      expect(
        formatFreshnessText(kNow.subtract(const Duration(minutes: 1)), now: kNow),
        'Updated 1 min ago',
      );
    });

    test('clock skew (future timestamp) reports Unknown, not "just now"', () {
      // A device/server clock running ahead yields a negative age. We cannot
      // place the data in time, so we must not claim it was just updated.
      expect(
        formatFreshnessText(kNow.add(const Duration(minutes: 10)), now: kNow),
        'Unknown',
      );
    });

    test('the epoch sentinel used by repositories is treated as missing', () {
      // ApiSearchRepository maps a missing timestamp to epoch 0. Without an
      // explicit guard this renders as "Stale" after ~56 years.
      expect(
        formatFreshnessText(DateTime.fromMillisecondsSinceEpoch(0), now: kNow),
        'Unknown',
      );
    });
  });

  group('formatFreshnessText — backend verdict is authoritative', () {
    test('backend STALE wins even when the timestamp looks recent', () {
      // The server knows the per-source threshold (POS sync vs manual entry),
      // so a client-side age calculation must not override it.
      expect(
        formatFreshnessText(
          kNow.subtract(const Duration(minutes: 2)),
          backendStatus: 'STALE',
          now: kNow,
        ),
        'Stale',
      );
    });

    test('backend STALE is matched case-insensitively and with padding', () {
      expect(
        formatFreshnessText(
          kNow.subtract(const Duration(minutes: 2)),
          backendStatus: ' stale ',
          now: kNow,
        ),
        'Stale',
      );
    });

    test('RECENTLY_UPDATED defers to the real timestamp', () {
      expect(
        formatFreshnessText(
          kNow.subtract(const Duration(minutes: 5)),
          backendStatus: 'RECENTLY_UPDATED',
          now: kNow,
        ),
        'Updated 5 min ago',
      );
    });
  });

  group('isFreshnessWarning', () {
    test('escalates Stale and Unknown only', () {
      expect(isFreshnessWarning('Stale'), isTrue);
      expect(isFreshnessWarning('Unknown'), isTrue);
      expect(isFreshnessWarning('Updated just now'), isFalse);
      expect(isFreshnessWarning('Updated 5 min ago'), isFalse);
      expect(isFreshnessWarning('Updated today'), isFalse);
      expect(isFreshnessWarning('Updated yesterday'), isFalse);
    });
  });

  group('kFreshnessDisclaimer', () {
    test('states availability can change and makes no guarantee', () {
      expect(kFreshnessDisclaimer, contains('Availability can change'));
      expect(kFreshnessDisclaimer, contains('confirm'));
      // The copy must never promise the item is held for the customer.
      expect(kFreshnessDisclaimer.toLowerCase(), isNot(contains('guaranteed')));
      expect(kFreshnessDisclaimer.toLowerCase(), isNot(contains('reserved')));
      expect(
        kFreshnessDisclaimer.toLowerCase(),
        isNot(contains('will be in stock')),
      );
    });
  });

  group('ShopProductResult freshness wiring', () {
    test('carries the backend verdict verbatim for rendering', () {
      final result = _result(
        lastUpdated: DateTime(2026, 3, 15, 14, 0),
        freshnessStatusRaw: 'STALE',
      );
      expect(result.freshnessStatusRaw, 'STALE');
    });

    test('stale backend status is not purchasable', () {
      final result = _result(
        isAvailable: true,
        availability: InventoryAvailability.inStock,
        freshness: FreshnessLevel.stale,
        freshnessStatusRaw: 'STALE',
      );
      expect(result.isPurchasableNow, isFalse);
    });
  });

  group('ShopProductResult derived properties', () {
    test('isPurchasableNow requires inStock AND fresh signal', () {
      expect(
        _result(
          isAvailable: true,
          availability: InventoryAvailability.inStock,
          freshness: FreshnessLevel.fresh,
        ).isPurchasableNow,
        isTrue,
      );
      expect(
        _result(
          isAvailable: true,
          availability: InventoryAvailability.inStock,
          freshness: FreshnessLevel.stale,
        ).isPurchasableNow,
        isFalse,
      );
      expect(
        _result(
          isAvailable: true,
          availability: InventoryAvailability.inStock,
          freshness: FreshnessLevel.unknown,
        ).isPurchasableNow,
        isFalse,
      );
      expect(
        _result(
          isAvailable: true,
          availability: InventoryAvailability.lowStock,
          freshness: FreshnessLevel.fresh,
        ).isPurchasableNow,
        isFalse,
      );
    });

    test('isOutOfStock reflects availability and isAvailable flag', () {
      expect(
        _result(
          isAvailable: false,
          availability: InventoryAvailability.outOfStock,
        ).isOutOfStock,
        isTrue,
      );
      expect(
        _result(
          isAvailable: false,
          availability: InventoryAvailability.inStock,
        ).isOutOfStock,
        isTrue,
      );
      expect(
        _result(
          isAvailable: true,
          availability: InventoryAvailability.inStock,
        ).isOutOfStock,
        isFalse,
      );
    });

    test('hasDiscount and discountPercent derive from MRP vs price', () {
      final discounted = _result(price: 90, mrp: 120);
      expect(discounted.hasDiscount, isTrue);
      expect(discounted.discountPercent, 25);

      final noMrp = _result(price: 90);
      expect(noMrp.hasDiscount, isFalse);
      expect(noMrp.discountPercent, 0);

      final sameMrp = _result(price: 90, mrp: 90);
      expect(sameMrp.hasDiscount, isFalse);
    });

    test('hasCoordinates reflects both lat and lng present', () {
      expect(_result(shopLat: 25.5, shopLng: 85.1).hasCoordinates, isTrue);
      expect(_result(shopLat: 25.5).hasCoordinates, isFalse);
      expect(_result().hasCoordinates, isFalse);
    });

    test('fromJson parses camelCase model response', () {
      final result = ShopProductResult.fromJson({
        'id': 'r1',
        'productId': 'p1',
        'productName': 'Amul Butter',
        'productImageUrl': 'http://img/butter.jpg',
        'shopId': 's1',
        'shopName': 'Local Mart',
        'price': 55.0,
        'isAvailable': true,
        'distanceInKm': 1.2,
        'shopRating': 4.4,
        'lastUpdated': '2026-08-23T10:00:00.000Z',
        'variant': '500g',
        'mrp': 68.0,
        'offerText': '10% OFF',
        'shopAddress': 'MG Road',
        'shopLatitude': 25.594,
        'shopLongitude': 85.137,
        'category': 'Groceries',
        'brand': 'Amul',
        'reviewCount': 42,
      });
      expect(result.productName, 'Amul Butter');
      expect(result.price, 55.0);
      expect(result.mrp, 68.0);
      expect(result.variant, '500g');
      expect(result.hasCoordinates, isTrue);
      expect(result.reviewCount, 42);
    });

    test('fromJson parses availability enum name', () {
      expect(
        ShopProductResult.fromJson({..._baseJson, 'availability': 'inStock'})
            .availability,
        InventoryAvailability.inStock,
      );
      expect(
        ShopProductResult.fromJson({..._baseJson, 'availability': 'outOfStock'})
            .availability,
        InventoryAvailability.outOfStock,
      );
      expect(
        ShopProductResult.fromJson({..._baseJson, 'availability': 'lowStock'})
            .availability,
        InventoryAvailability.lowStock,
      );
      // Missing availability defaults to unknown
      expect(
        ShopProductResult.fromJson(_baseJson).availability,
        InventoryAvailability.unknown,
      );
    });
  });

  group('SortOption', () {
    test('includes all required options', () {
      expect(
        SortOption.values,
        containsAll([
          SortOption.nearest,
          SortOption.lowestPrice,
          SortOption.highestRated,
          SortOption.availability,
          SortOption.relevance,
          SortOption.recentlyUpdated,
        ]),
      );
    });
  });
}

Map<String, dynamic> get _baseJson => {
  'id': 'r1',
  'productId': 'p1',
  'productName': 'Test',
  'productImageUrl': '',
  'shopId': 's1',
  'shopName': 'Shop',
  'price': 10.0,
  'isAvailable': true,
  'distanceInKm': 1.0,
  'shopRating': 4.0,
  'lastUpdated': '2026-08-23T10:00:00.000Z',
};

ShopProductResult _result({
  bool isAvailable = true,
  InventoryAvailability availability = InventoryAvailability.inStock,
  FreshnessLevel freshness = FreshnessLevel.fresh,
  double? price = 100,
  double? mrp,
  double? shopLat,
  double? shopLng,
  DateTime? lastUpdated,
  String? freshnessStatusRaw,
}) {
  return ShopProductResult(
    id: 'r1',
    productId: 'p1',
    productName: 'Test',
    productImageUrl: '',
    shopId: 's1',
    shopName: 'Shop',
    price: price ?? 100,
    isAvailable: isAvailable,
    distanceInKm: 1.0,
    shopRating: 4.0,
    lastUpdated: lastUpdated ?? DateTime.now(),
    mrp: mrp,
    shopLatitude: shopLat,
    shopLongitude: shopLng,
    availability: availability,
    freshness: freshness,
    freshnessStatusRaw: freshnessStatusRaw,
  );
}
