import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/features/product_details/domain/models/product_details_models.dart';

void main() {
  group('ShopInventoryOffer.isOutOfStock', () {
    test('unavailable flag alone means out of stock', () {
      expect(_offer(isAvailable: false).isOutOfStock, isTrue);
    });

    test('explicit out-of-stock status is honoured', () {
      expect(
        _offer(isAvailable: true, stockStatus: 'OUT_OF_STOCK').isOutOfStock,
        isTrue,
      );
    });

    test('in-stock status is not out of stock', () {
      expect(
        _offer(isAvailable: true, stockStatus: 'IN_STOCK').isOutOfStock,
        isFalse,
      );
    });

    test('an unknown status is not treated as out of stock', () {
      // Absence of a status is not evidence of absence of stock.
      expect(
        _offer(isAvailable: true, stockStatus: null).isOutOfStock,
        isFalse,
      );
      expect(
        _offer(isAvailable: true, stockStatus: 'SOMETHING_NEW').isOutOfStock,
        isFalse,
      );
    });
  });

  group('ShopInventoryOffer open/closed derivation', () {
    test('confirmed open and closed are distinguished from unknown', () {
      expect(_offer(isOpenNow: true).isConfirmedOpen, isTrue);
      expect(_offer(isOpenNow: true).isConfirmedClosed, isFalse);

      expect(_offer(isOpenNow: false).isConfirmedClosed, isTrue);
      expect(_offer(isOpenNow: false).isConfirmedOpen, isFalse);

      // Unknown is neither — it must never be read as "open".
      expect(_offer(isOpenNow: null).isConfirmedOpen, isFalse);
      expect(_offer(isOpenNow: null).isConfirmedClosed, isFalse);
    });
  });

  group('ShopInventoryOffer discount maths', () {
    test('a price below MRP is a discount', () {
      final discounted = _offer(price: 90, mrp: 120);
      expect(discounted.hasDiscount, isTrue);
      expect(discounted.discountPercent, 25);
    });

    test('price at or above MRP is not a discount', () {
      expect(_offer(price: 120, mrp: 120).hasDiscount, isFalse);
      expect(_offer(price: 130, mrp: 120).hasDiscount, isFalse);
      expect(_offer(price: 100, mrp: null).hasDiscount, isFalse);
      expect(_offer(price: 130, mrp: 120).discountPercent, 0);
    });
  });

  group('ProductDetails price comparison', () {
    test('lowest and highest use only in-stock offers', () {
      final details = _details([
        _offer(shopId: 'a', price: 50, isAvailable: true),
        _offer(shopId: 'b', price: 300, isAvailable: true),
        // Cheapest, but out of stock — must not set the current price.
        _offer(shopId: 'c', price: 10, isAvailable: false),
      ]);

      expect(details.lowestPrice, 50);
      expect(details.highestPrice, 300);
      expect(details.priceSpread, 250);
      expect(details.comparableOffers.length, 2);
    });

    test('no in-stock offers yields a null price, not a fabricated one', () {
      final details = _details([
        _offer(shopId: 'a', price: 50, isAvailable: false),
      ]);

      expect(details.lowestPrice, isNull);
      expect(details.highestPrice, isNull);
      expect(details.priceSpread, isNull);
      expect(details.cheapestOffer, isNull);
    });

    test('a single price has no spread to report', () {
      final details = _details([
        _offer(shopId: 'a', price: 50, isAvailable: true),
      ]);

      expect(details.lowestPrice, 50);
      expect(details.priceSpread, isNull);
    });

    test('identical prices across shops have no spread', () {
      final details = _details([
        _offer(shopId: 'a', price: 50, isAvailable: true),
        _offer(shopId: 'b', price: 50, isAvailable: true),
      ]);

      expect(details.priceSpread, isNull);
      expect(details.lowestPrice, 50);
    });

    test('comparableOffers is sorted cheapest first', () {
      final details = _details([
        _offer(shopId: 'a', price: 300, isAvailable: true),
        _offer(shopId: 'b', price: 100, isAvailable: true),
      ]);

      expect(details.comparableOffers.map((o) => o.price).toList(), [100, 300]);
    });

    test('allOffersSorted keeps out-of-stock shops visible', () {
      final details = _details([
        _offer(shopId: 'a', price: 300, isAvailable: true),
        _offer(shopId: 'b', price: 10, isAvailable: false),
      ]);

      expect(details.allOffersSorted.length, 2);
      expect(details.allOffersSorted.first.price, 10);
    });

    test('nearestInStockOffer picks the closest available shop', () {
      final details = _details([
        _offer(shopId: 'far', price: 50, isAvailable: true, distanceInKm: 9),
        _offer(shopId: 'near', price: 60, isAvailable: true, distanceInKm: 1),
        // Nearest overall but unavailable — not eligible.
        _offer(
          shopId: 'offline',
          price: 40,
          isAvailable: false,
          distanceInKm: 0.1,
        ),
      ]);

      expect(details.nearestInStockOffer?.shopId, 'near');
    });
  });

  group('ProductDetails.offersWithDeals', () {
    test('includes a sub-MRP price even without offer text', () {
      final details = _details([_offer(shopId: 'a', price: 90, mrp: 100)]);
      expect(details.offersWithDeals.length, 1);
    });

    test('includes an offer label even at full MRP', () {
      final details = _details([
        _offer(shopId: 'a', price: 100, mrp: 100, offerText: 'Buy 2 get 1'),
      ]);
      expect(details.offersWithDeals.length, 1);
    });

    test('excludes shops with neither a discount nor an offer label', () {
      final details = _details([
        _offer(shopId: 'a', price: 100, mrp: 100),
        _offer(shopId: 'b', price: 100, mrp: null, offerText: ''),
      ]);
      expect(details.offersWithDeals, isEmpty);
    });

    test('orders the biggest discount first', () {
      final details = _details([
        _offer(shopId: 'small', price: 95, mrp: 100),
        _offer(shopId: 'large', price: 50, mrp: 100),
      ]);
      expect(details.offersWithDeals.first.shopId, 'large');
    });
  });

  // The rule these tests defend: a cached payload may still SHOW the product
  // (name, brand, images, description are stable), but it may never CLAIM
  // anything about current stock, price, offers or availability. A warning
  // banner above a stale "In Stock" tile is not disclosure — the tile is the
  // claim, and it is the part the customer acts on.
  group('ProductDetails cache honesty', () {
    List<ShopInventoryOffer> cachedOffers() => [
      _offer(shopId: 'a', price: 50, isAvailable: true),
      _offer(shopId: 'b', price: 90, mrp: 120, isAvailable: true),
    ];

    ProductDetails cached([List<ShopInventoryOffer>? offers]) {
      final now = DateTime.now();
      return ProductDetails(
        product: const ProductMasterDetails(
          id: 'p1',
          name: 'Test Product',
          brand: 'Brand',
          category: 'Category',
        ),
        shopOffers: offers ?? cachedOffers(),
        servedFromCache: true,
        cachedAt: now.subtract(const Duration(minutes: 30)),
      );
    }

    test('live data is trusted and cached data is not', () {
      expect(_details(cachedOffers()).hasLiveShopData, isTrue);
      expect(cached().hasLiveShopData, isFalse);
      expect(cached().isStale, isTrue);
    });

    test('cached offers are withheld entirely', () {
      // Not "shown with a warning" — withheld, because a stale tile is worse
      // than no tile: it invites a wasted trip to the shop.
      expect(cached().liveOffers, isEmpty);
      expect(cached().comparableOffers, isEmpty);
      expect(cached().allOffersSorted, isEmpty);
    });

    test('cached data reports no prices', () {
      final details = cached();
      // A remembered price is not a current one, so these must be null rather
      // than 50 / 90.
      expect(details.lowestPrice, isNull);
      expect(details.highestPrice, isNull);
      expect(details.priceSpread, isNull);
      expect(details.cheapestOffer, isNull);
      expect(details.nearestInStockOffer, isNull);
    });

    test('cached data reports no deals', () {
      // The offer in the cache was genuinely discounted when it was written;
      // it may have expired since, and no end time was cached to check.
      expect(cached().offersWithDeals, isEmpty);
    });

    test('the raw cached payload is still intact for analytics/debug', () {
      // Suppressing the LIVE view must not destroy the data itself — the raw
      // list is the record of what the server last said.
      expect(cached().shopOffers.length, 2);
    });

    test('a "Last updated" label is shown for cache and withheld for live', () {
      expect(cached().lastUpdatedLabel, isNotNull);
      expect(_details(cachedOffers()).lastUpdatedLabel, isNull);
    });

    test('an empty cache yields the same empty view as an empty live payload', () {
      // A cached payload with no offers must not be distinguishable from a live
      // one with no offers: neither supports any availability claim.
      final noOffers = cached([]);
      expect(noOffers.liveOffers, isEmpty);
      expect(noOffers.lowestPrice, isNull);
    });
  });
}

ShopInventoryOffer _offer({
  String shopId = 's1',
  String shopName = 'Shop',
  double price = 100,
  double? mrp,
  double distanceInKm = 1,
  double rating = 4,
  bool isAvailable = true,
  String? stockStatus = 'IN_STOCK',
  String? freshnessStatus,
  String? offerText,
  bool? isOpenNow,
  bool? isAcceptingOrders,
  DateTime? lastUpdated,
}) {
  return ShopInventoryOffer(
    shopId: shopId,
    shopName: shopName,
    shopImageUrl: '',
    price: price,
    mrp: mrp,
    distanceInKm: distanceInKm,
    rating: rating,
    isAvailable: isAvailable,
    lastUpdated: lastUpdated ?? DateTime.now(),
    stockStatus: stockStatus,
    freshnessStatus: freshnessStatus,
    offerText: offerText,
    isOpenNow: isOpenNow,
    isAcceptingOrders: isAcceptingOrders,
  );
}

ProductDetails _details(List<ShopInventoryOffer> offers) {
  return ProductDetails(
    product: const ProductMasterDetails(
      id: 'p1',
      name: 'Test Product',
      brand: 'Brand',
      category: 'Category',
    ),
    shopOffers: offers,
  );
}
