import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/features/shop_details/domain/models/business_profile_models.dart';

/// Business-profile parsing (Master Spec §86-§89).
///
/// This layer is where a payload that does not match expectations must degrade
/// instead of breaking a shop profile, so these tests are mostly about tolerance:
/// a missing field, a null, a number-as-string, an unknown extra key.
void main() {
  group('RestaurantProfile', () {
    test('parses a full payload', () {
      final profile = RestaurantProfile.tryParse({
        'id': 3,
        'shop_id': 7,
        'name': 'Annapurna',
        'cuisine_types': ['North Indian', 'Chinese', '  ', 42],
        'dining_available': true,
        'takeaway_available': false,
        'avg_cost_for_two': '600',
        'rating': 4.4,
        'review_count': 12,
        'veg_only': false,
        'phone': '+91 98765 43210',
        'address': '14 Food Street',
        'latitude': 28.716,
        'longitude': 77.118,
        'menu_categories': [
          {
            'id': 1,
            'name': 'Main Course',
            'items': [
              {'id': 11, 'name': 'Paneer Masala', 'price': 240, 'veg': true},
              {'id': 12, 'name': 'Biryani', 'spicy': true, 'price': 280},
            ],
          },
        ],
      });

      expect(profile, isNotNull);
      expect(profile!.shopId, '7');
      // Blank and non-string cuisines are dropped rather than rendered.
      expect(profile.cuisineTypes, ['North Indian', 'Chinese']);
      expect(profile.avgCostForTwo, 600.0);
      expect(profile.diningAvailable, isTrue);
      expect(profile.takeawayAvailable, isFalse);
      expect(profile.menu, hasLength(1));
      expect(profile.menu.first.items, hasLength(2));
      expect(profile.menu.first.items.first.veg, isTrue);
      expect(profile.menu.first.items.last.spicy, isTrue);
      // Absent flag defaults to available, matching the backend default.
      expect(profile.menu.first.items.last.availableToday, isTrue);
    });

    test('a nameless or non-map payload yields null', () {
      expect(RestaurantProfile.tryParse(null), isNull);
      expect(RestaurantProfile.tryParse('restaurant'), isNull);
      expect(RestaurantProfile.tryParse({'id': 1}), isNull);
      expect(RestaurantProfile.tryParse({'name': '   '}), isNull);
    });

    test('an unknown extra key does not break parsing', () {
      final profile = RestaurantProfile.tryParse({
        'name': 'Annapurna',
        'live_streaming': true,
        'menu_categories': <Object?>[],
      });
      expect(profile, isNotNull);
      expect(profile!.menu, isEmpty);
    });

    test('a menu item with no name is skipped, its siblings survive', () {
      final profile = RestaurantProfile.tryParse({
        'name': 'Annapurna',
        'menu_categories': [
          {
            'name': 'Breads',
            'items': [
              {'name': ''},
              {'id': 2},
              'not-a-map',
              {'name': 'Naan', 'price': 40},
            ],
          },
        ],
      });
      expect(profile!.menu.first.items.map((i) => i.name), ['Naan']);
    });

    test('a null menu is an empty menu, not a crash', () {
      final profile = RestaurantProfile.tryParse({
        'name': 'Annapurna',
        'menu_categories': null,
      });
      expect(profile!.menu, isEmpty);
    });
  });

  group('TransportServiceProfile', () {
    test('parses provider, fleet and services', () {
      final profile = TransportServiceProfile.tryParse({
        'id': 9001,
        'company_name': 'Raftaar City Movers',
        'verification_status': 'VERIFIED',
        'rating': 4.3,
        'review_count': 211,
        'vehicles': [
          {
            'id': 1,
            'vehicle_type': 'SUV',
            'make': 'Toyota',
            'model': 'Innova',
            'capacity_passengers': 6,
            'ac_available': true,
          },
          {'id': 2},
        ],
        'services': [
          {
            'id': 5,
            'service_type': 'AIRPORT',
            'name': 'Airport drops',
            'base_price': 650,
            'price_unit': 'PER_TRIP',
          },
        ],
      });

      expect(profile, isNotNull);
      expect(profile!.id, '9001');
      // A vehicle with no type cannot be described to a customer, so it is
      // skipped — the fleet shows only what it can name.
      expect(profile.vehicles, hasLength(1));
      expect(profile.vehicles.first.capacityPassengers, 6);
      expect(profile.services.single.name, 'Airport drops');
      expect(profile.services.single.basePrice, 650.0);
    });

    test('a service with only a type still gets a name', () {
      final profile = TransportServiceProfile.tryParse({
        'company_name': 'Ola Hub',
        'services': [
          {'service_type': 'FAMILY_TOUR'},
        ],
      });
      expect(profile!.services.single.name, 'FAMILY_TOUR');
    });

    test('an unnamed provider yields null', () {
      expect(TransportServiceProfile.tryParse({'id': 1}), isNull);
      expect(TransportServiceProfile.tryParse(null), isNull);
    });
  });

  group('TransportQuoteRequest', () {
    test('serializes exactly the fields the backend contract accepts', () {
      final json = TransportQuoteRequest(
        providerId: '9001',
        tripPurpose: 'AIRPORT',
        pickupAddress: 'Connaught Place',
        destinationAddress: 'IGI Airport',
        tripDate: DateTime(2026, 3, 7),
        tripDays: 2,
        passengerCount: 3,
        vehicleId: '5',
        notes: '  Please bring a child seat  ',
      ).toJson();

      expect(json['provider_id'], 9001);
      expect(json['vehicle_id'], 5);
      expect(json['trip_purpose'], 'AIRPORT');
      expect(json['pickup_address'], 'Connaught Place');
      expect(json['destination_address'], 'IGI Airport');
      // A date, not a timestamp: the contract types it as a date.
      expect(json['trip_date'], '2026-03-07');
      expect(json['trip_days'], 2);
      expect(json['passenger_count'], 3);
      expect(json['notes'], 'Please bring a child seat');
    });

    test('omits the optional keys when unset', () {
      final json = TransportQuoteRequest(
        providerId: '9001',
        tripPurpose: 'LOCAL_TRAVEL',
        pickupAddress: 'A',
        destinationAddress: 'B',
        tripDate: DateTime(2026, 1, 2),
      ).toJson();

      expect(json.containsKey('vehicle_id'), isFalse);
      expect(json.containsKey('notes'), isFalse);
    });

    test('a non-numeric provider id is passed through rather than dropped', () {
      // The backend types it as an int, so this is a contract mismatch either
      // way — sending the value beats silently sending null, and the server
      // answers with a validation error the form can show.
      final json = TransportQuoteRequest(
        providerId: 'abc',
        tripPurpose: 'OTHER',
        pickupAddress: 'A',
        destinationAddress: 'B',
        tripDate: DateTime(2026, 1, 2),
      ).toJson();
      expect(json['provider_id'], 'abc');
    });
  });

  group('TransportQuoteReceipt', () {
    test('parses an acknowledgement with no price', () {
      final receipt = TransportQuoteReceipt.tryParse({
        'id': 55,
        'status': 'REQUESTED',
      });
      expect(receipt, isNotNull);
      expect(receipt!.quoteId, '55');
      expect(receipt.status, 'REQUESTED');
    });

    test('an acknowledgement without an id is not a confirmation', () {
      expect(TransportQuoteReceipt.tryParse({'status': 'OK'}), isNull);
      expect(TransportQuoteReceipt.tryParse('ok'), isNull);
    });
  });
}
