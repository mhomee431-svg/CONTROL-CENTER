import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_customer_app/features/search/domain/models/search_models.dart';

void main() {
  group('ShopProductResult derived properties', () {
    test('isPurchasableNow requires inStock AND fresh signal', () {
      expect(_result(isAvailable: true, availability: InventoryAvailability.inStock, freshness: FreshnessLevel.fresh).isPurchasableNow, isTrue);
      expect(_result(isAvailable: true, availability: InventoryAvailability.inStock, freshness: FreshnessLevel.stale).isPurchasableNow, isFalse);
      expect(_result(isAvailable: true, availability: InventoryAvailability.inStock, freshness: FreshnessLevel.unknown).isPurchasableNow, isFalse);
      expect(_result(isAvailable: true, availability: InventoryAvailability.lowStock, freshness: FreshnessLevel.fresh).isPurchasableNow, isFalse);
    });

    test('isOutOfStock reflects availability and isAvailable flag', () {
      expect(_result(isAvailable: false, availability: InventoryAvailability.outOfStock).isOutOfStock, isTrue);
      expect(_result(isAvailable: false, availability: InventoryAvailability.inStock).isOutOfStock, isTrue);
      expect(_result(isAvailable: true, availability: InventoryAvailability.inStock).isOutOfStock, isFalse);
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
      expect(ShopProductResult.fromJson({..._baseJson, 'availability': 'inStock'}).availability, InventoryAvailability.inStock);
      expect(ShopProductResult.fromJson({..._baseJson, 'availability': 'outOfStock'}).availability, InventoryAvailability.outOfStock);
      expect(ShopProductResult.fromJson({..._baseJson, 'availability': 'lowStock'}).availability, InventoryAvailability.lowStock);
      // Missing availability defaults to unknown
      expect(ShopProductResult.fromJson(_baseJson).availability, InventoryAvailability.unknown);
    });
  });

  group('SortOption', () {
    test('includes all required options', () {
      expect(SortOption.values, containsAll([
        SortOption.nearest,
        SortOption.lowestPrice,
        SortOption.highestRated,
        SortOption.availability,
        SortOption.relevance,
        SortOption.recentlyUpdated,
      ]));
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
    lastUpdated: DateTime.now(),
    mrp: mrp,
    shopLatitude: shopLat,
    shopLongitude: shopLng,
    availability: availability,
    freshness: freshness,
  );
}