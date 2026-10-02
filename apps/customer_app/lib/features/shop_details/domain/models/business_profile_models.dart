/// Business profiles for non-product businesses (Master Spec §86-§89).
///
/// WHY A SEPARATE MODEL FILE
/// -------------------------
/// [ShopProfile] carries the IDENTITY every business shares (name, rating,
/// address, contact, capabilities). This file carries the EXTRA sections that
/// only exist for a capability:
///
///  * a restaurant's display-only [RestaurantProfile] (from `/restaurants`);
///  * a transport / travel provider's [TransportServiceProfile] (from
///    `/transport`);
///
///  kept apart so a product shop never pays for — or sees — fields that cannot
///  exist for it.
///
/// Tolerantly parsed, on purpose: the app must render a menu whose newest item
/// carries a field this build has never heard of, and must still render the
/// rest of it. Unknown extra keys are simply ignored, and rows that cannot be
/// read are skipped rather than failing the whole profile.
library;

/// Display prices without stock semantics, exactly the way the backend serves a
/// restaurant menu (Rule 4: discovery-only).
class RestaurantMenuItem {
  final String id;
  final String name;
  final String description;

  /// Reference price for the customer to read. Display-only: there is no cart,
  /// no checkout and no delivery behind it, so it is never combined with a
  /// quantity or a "buy" action.
  final double? price;
  final bool veg;
  final bool spicy;
  final bool availableToday;

  const RestaurantMenuItem({
    required this.id,
    required this.name,
    this.description = '',
    this.price,
    this.veg = false,
    this.spicy = false,
    this.availableToday = true,
  });

  static RestaurantMenuItem? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final name = _string(raw['name']);
    if (name.isEmpty) return null;
    final price = _double(raw['price']);
    return RestaurantMenuItem(
      id: _string(raw['id'], fallback: name),
      name: name,
      description: _string(raw['description']),
      price: price,
      veg: _bool(raw['veg']),
      spicy: _bool(raw['spicy']),
      availableToday: raw['is_available_today'] == null
          ? true
          : _bool(raw['is_available_today']),
    );
  }
}

/// One menu section of [RestaurantProfile.menu].
class RestaurantMenuSection {
  final String id;
  final String name;
  final String description;
  final List<RestaurantMenuItem> items;

  const RestaurantMenuSection({
    required this.id,
    required this.name,
    this.description = '',
    this.items = const [],
  });

  static RestaurantMenuSection? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final name = _string(raw['name']);
    if (name.isEmpty) return null;
    final items = <RestaurantMenuItem>[];
    final rawItems = raw['items'];
    if (rawItems is List) {
      for (final entry in rawItems) {
        final item = RestaurantMenuItem.tryParse(entry);
        if (item != null) items.add(item);
      }
    }
    return RestaurantMenuSection(
      id: _string(raw['id'], fallback: name),
      name: name,
      description: _string(raw['description']),
      items: items,
    );
  }
}

/// The restaurant side of a business whose capabilities include `menu`.
///
/// Identity (name, rating, address, hours) stays on [ShopProfile]; this carries
/// only what the restaurant endpoints add: cuisine, dining/takeaway flags and
/// the display-only menu.
class RestaurantProfile {
  final String id;
  final String shopId;
  final String name;
  final List<String> cuisineTypes;
  final bool diningAvailable;
  final bool takeawayAvailable;
  final double? avgCostForTwo;
  final double rating;
  final int reviewCount;
  final bool vegOnly;
  final String phone;
  final String address;
  final double latitude;
  final double longitude;
  final List<RestaurantMenuSection> menu;

  const RestaurantProfile({
    required this.id,
    required this.shopId,
    required this.name,
    this.cuisineTypes = const [],
    this.diningAvailable = true,
    this.takeawayAvailable = true,
    this.avgCostForTwo,
    this.rating = 0,
    this.reviewCount = 0,
    this.vegOnly = false,
    this.phone = '',
    this.address = '',
    this.latitude = 0,
    this.longitude = 0,
    this.menu = const [],
  });

  static RestaurantProfile? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final name = _string(raw['name']);
    // A restaurant with no name cannot be shown to a customer, and rendering an
    // empty row would be worse than rendering no menu — so this is not a profile.
    if (name.isEmpty) return null;
    final menu = <RestaurantMenuSection>[];
    final rawMenu = raw['menu_categories'];
    if (rawMenu is List) {
      for (final entry in rawMenu) {
        final section = RestaurantMenuSection.tryParse(entry);
        if (section != null) menu.add(section);
      }
    }
    final cuisines = <String>[];
    final rawCuisines = raw['cuisine_types'];
    if (rawCuisines is List) {
      for (final entry in rawCuisines) {
        if (entry is String && entry.trim().isNotEmpty) {
          cuisines.add(entry.trim());
        }
      }
    }
    return RestaurantProfile(
      id: _string(raw['id'], fallback: name),
      shopId: _string(raw['shop_id']),
      name: name,
      cuisineTypes: cuisines,
      diningAvailable: raw['dining_available'] == null
          ? true
          : _bool(raw['dining_available']),
      takeawayAvailable: raw['takeaway_available'] == null
          ? true
          : _bool(raw['takeaway_available']),
      avgCostForTwo: _double(raw['avg_cost_for_two']),
      rating: _double(raw['rating']) ?? 0,
      reviewCount: _int(raw['review_count']) ?? 0,
      vegOnly: _bool(raw['veg_only']),
      phone: _string(raw['phone']),
      address: _string(raw['address']),
      latitude: _double(raw['latitude']) ?? 0,
      longitude: _double(raw['longitude']) ?? 0,
      menu: menu,
    );
  }
}

/// One vehicle of a transport provider's fleet.
class ProviderVehicle {
  final String id;
  final String vehicleType;
  final String make;
  final String model;
  final String registrationNumber;
  final int capacityPassengers;
  final bool acAvailable;
  final bool isActive;

  const ProviderVehicle({
    required this.id,
    required this.vehicleType,
    this.make = '',
    this.model = '',
    this.registrationNumber = '',
    this.capacityPassengers = 0,
    this.acAvailable = false,
    this.isActive = true,
  });

  static ProviderVehicle? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final vehicleType = _string(raw['vehicle_type']);
    if (vehicleType.isEmpty) return null;
    return ProviderVehicle(
      id: _string(raw['id'], fallback: vehicleType),
      vehicleType: vehicleType,
      make: _string(raw['make']),
      model: _string(raw['model']),
      registrationNumber: _string(raw['registration_number']),
      capacityPassengers: _int(raw['capacity_passengers']) ?? 0,
      acAvailable: _bool(raw['ac_available']),
      isActive: raw['is_active'] == null ? true : _bool(raw['is_active']),
    );
  }
}

/// One bookable service a transport provider offers.
class TransportServiceOffering {
  final String id;
  final String serviceType;
  final String name;
  final double basePrice;
  final String priceUnit;
  final bool isActive;

  const TransportServiceOffering({
    required this.id,
    required this.serviceType,
    required this.name,
    this.basePrice = 0,
    this.priceUnit = '',
    this.isActive = true,
  });

  static TransportServiceOffering? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final name = _string(raw['name']);
    final serviceType = _string(raw['service_type']);
    if (name.isEmpty && serviceType.isEmpty) return null;
    return TransportServiceOffering(
      id: _string(raw['id'], fallback: name.isEmpty ? serviceType : name),
      serviceType: serviceType,
      name: name.isEmpty ? serviceType : name,
      basePrice: _double(raw['base_price']) ?? 0,
      priceUnit: _string(raw['price_unit']),
      isActive: raw['is_active'] == null ? true : _bool(raw['is_active']),
    );
  }
}

/// The transport / travel side of a business whose capabilities include
/// `service_profile`: the provider, its fleet and its bookable services.
///
/// What it deliberately does NOT carry: service prices are reference figures
/// from `/transport` (every trip is QUOTED), never a cart or a checkout. A
/// booking only exists once the customer requests a quote and the provider
/// accepts it.
class TransportServiceProfile {
  final String id;
  final String companyName;
  final String licenseNumber;
  final String verificationStatus;
  final double rating;
  final int reviewCount;
  final List<ProviderVehicle> vehicles;
  final List<TransportServiceOffering> services;

  const TransportServiceProfile({
    required this.id,
    required this.companyName,
    this.licenseNumber = '',
    this.verificationStatus = '',
    this.rating = 0,
    this.reviewCount = 0,
    this.vehicles = const [],
    this.services = const [],
  });

  static TransportServiceProfile? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final companyName = _string(raw['company_name']);
    if (companyName.isEmpty) return null;
    final vehicles = <ProviderVehicle>[];
    final rawVehicles = raw['vehicles'];
    if (rawVehicles is List) {
      for (final entry in rawVehicles) {
        final vehicle = ProviderVehicle.tryParse(entry);
        if (vehicle != null) vehicles.add(vehicle);
      }
    }
    final services = <TransportServiceOffering>[];
    final rawServices = raw['services'];
    if (rawServices is List) {
      for (final entry in rawServices) {
        final service = TransportServiceOffering.tryParse(entry);
        if (service != null) services.add(service);
      }
    }
    return TransportServiceProfile(
      id: _string(raw['id'], fallback: companyName),
      companyName: companyName,
      licenseNumber: _string(raw['license_number']),
      verificationStatus: _string(raw['verification_status']),
      rating: _double(raw['rating']) ?? 0,
      reviewCount: _int(raw['review_count']) ?? 0,
      vehicles: vehicles,
      services: services,
    );
  }
}

/// What the customer writes to ask a provider for a trip price.
///
/// Field names mirror `TransportQuoteCreate` on the backend on purpose: this
/// object is serialized straight into `POST /transport/quotes`, so the form
/// cannot ask for something the contract does not accept. The confirmed price
/// comes back FROM the provider — never computed on the device.
class TransportQuoteRequest {
  final String providerId;
  final String tripPurpose;
  final String pickupAddress;
  final String destinationAddress;
  final DateTime tripDate;
  final int tripDays;
  final int passengerCount;
  final String? vehicleId;
  final String notes;

  const TransportQuoteRequest({
    required this.providerId,
    required this.tripPurpose,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.tripDate,
    this.tripDays = 1,
    this.passengerCount = 1,
    this.vehicleId,
    this.notes = '',
  });

  Map<String, dynamic> toJson() => {
    'provider_id': int.tryParse(providerId) ?? providerId,
    if ((vehicleId ?? '').isNotEmpty)
      'vehicle_id': int.tryParse(vehicleId!) ?? vehicleId,
    'trip_purpose': tripPurpose,
    'pickup_address': pickupAddress,
    'destination_address': destinationAddress,
    'trip_date': tripDate.toIso8601String().split('T').first,
    'trip_days': tripDays,
    'passenger_count': passengerCount,
    if (notes.trim().isNotEmpty) 'notes': notes.trim(),
  };
}

/// One of the customer's own quote requests, as the trips list shows it.
///
/// [quotedAmount] is the PROVIDER's price and is null until they have answered —
/// a pending request has no price, and rendering the column's zero default as
/// "₹0" would tell the customer a trip is free. [canAccept] is the single
/// question the view asks, derived from the backend's status vocabulary rather
/// than re-decided at each call site.
class TransportQuote {
  final String id;
  final String providerId;
  final String providerName;
  final String status;
  final String tripPurpose;
  final String pickupAddress;
  final String destinationAddress;
  final String tripDate;
  final int tripDays;
  final int passengerCount;
  final double? quotedAmount;
  final String currency;
  final String notes;

  const TransportQuote({
    required this.id,
    required this.providerId,
    this.providerName = '',
    this.status = '',
    this.tripPurpose = '',
    this.pickupAddress = '',
    this.destinationAddress = '',
    this.tripDate = '',
    this.tripDays = 1,
    this.passengerCount = 1,
    this.quotedAmount,
    this.currency = 'INR',
    this.notes = '',
  });

  /// The provider has answered and the customer can accept.
  bool get canAccept => status.toUpperCase() == 'QUOTED';

  /// Waiting for the provider. No price yet, and nothing to accept.
  bool get isPending => status.toUpperCase() == 'REQUESTED';

  /// Accepted — this trip became a booking.
  bool get isAccepted => status.toUpperCase() == 'ACCEPTED';

  /// Closed without becoming a booking.
  bool get isClosed {
    final key = status.toUpperCase();
    return key == 'REJECTED' || key == 'EXPIRED';
  }

  static TransportQuote? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = _string(raw['id']);
    if (id.isEmpty) return null;
    return TransportQuote(
      id: id,
      providerId: _string(raw['provider_id']),
      providerName: _string(raw['provider_name']),
      status: _string(raw['status']),
      tripPurpose: _string(raw['trip_purpose']),
      pickupAddress: _string(raw['pickup_address']),
      destinationAddress: _string(raw['destination_address']),
      tripDate: _string(raw['trip_date']),
      tripDays: _int(raw['trip_days']) ?? 1,
      passengerCount: _int(raw['passenger_count']) ?? 1,
      quotedAmount: _double(raw['quote_amount']),
      currency: _string(raw['currency'], fallback: 'INR'),
      notes: _string(raw['notes']),
    );
  }
}

/// The backend's acknowledgement that a quote request landed.
///
/// The price is NOT here: the provider quotes it later (see
/// `/transport/quotes/{id}/accept`). Showing a price now would be inventing one.
class TransportQuoteReceipt {
  final String quoteId;
  final String status;

  const TransportQuoteReceipt({required this.quoteId, this.status = ''});

  static TransportQuoteReceipt? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = _string(raw['id']);
    if (id.isEmpty) return null;
    return TransportQuoteReceipt(quoteId: id, status: _string(raw['status']));
  }
}

/// One status change on a booking — the trip's history.
class TransportBookingStatusEvent {
  final String fromStatus;
  final String toStatus;
  final String changedAt;
  final String note;

  const TransportBookingStatusEvent({
    this.fromStatus = '',
    required this.toStatus,
    this.changedAt = '',
    this.note = '',
  });

  static TransportBookingStatusEvent? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final to = _string(raw['to_status']);
    if (to.isEmpty) return null;
    return TransportBookingStatusEvent(
      fromStatus: _string(raw['from_status']),
      toStatus: to,
      changedAt: _string(raw['changed_at']),
      note: _string(raw['note']),
    );
  }
}

/// A confirmed transport booking — a SERVICE booking, never a product order.
///
/// Carries the AGREED amount (the price the customer accepted, the only amount
/// ever charged) rather than a total the app could recompute differently from
/// the provider.
class TransportBooking {
  final String id;
  final String quoteId;
  final String bookingRef;
  final String status;
  final String pickupAddress;
  final String destination;
  final String tripDate;
  final int tripDays;
  final int passengerCount;
  final double agreedAmount;
  final String currency;
  final List<TransportBookingStatusEvent> statusHistory;

  const TransportBooking({
    required this.id,
    this.quoteId = '',
    required this.bookingRef,
    this.status = '',
    this.pickupAddress = '',
    this.destination = '',
    this.tripDate = '',
    this.tripDays = 1,
    this.passengerCount = 1,
    this.agreedAmount = 0,
    this.currency = 'INR',
    this.statusHistory = const [],
  });

  /// A booking in a state where cancelling still means something. A completed or
  /// already-cancelled booking cannot be cancelled, and offering the button anyway
  /// is exactly the dead control the error-handling rules forbid.
  bool get canCancel {
    final key = status.toUpperCase();
    return key != 'COMPLETED' && key != 'CANCELLED';
  }

  static TransportBooking? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final ref = _string(raw['booking_ref']);
    if (ref.isEmpty) return null;
    final history = <TransportBookingStatusEvent>[];
    final rawHistory = raw['status_history'];
    if (rawHistory is List) {
      for (final entry in rawHistory) {
        final event = TransportBookingStatusEvent.tryParse(entry);
        if (event != null) history.add(event);
      }
    }
    return TransportBooking(
      id: _string(raw['id'], fallback: ref),
      quoteId: _string(raw['quote_id']),
      bookingRef: ref,
      status: _string(raw['status']),
      pickupAddress: _string(raw['pickup_address']),
      destination: _string(raw['destination']),
      tripDate: _string(raw['trip_date']),
      tripDays: _int(raw['trip_days']) ?? 1,
      passengerCount: _int(raw['passenger_count']) ?? 1,
      agreedAmount: _double(raw['agreed_amount']) ?? 0,
      currency: _string(raw['currency'], fallback: 'INR'),
      statusHistory: history,
    );
  }
}

/// The customer's transport trips: open quotes plus confirmed bookings.
///
/// ONE object for both, because the customer's real question is "what is
/// happening with my trip?", and splitting that across two screens to answer one
/// question is the fragmentation a single source of truth exists to prevent.
class TransportTrips {
  final List<TransportQuote> quotes;
  final List<TransportBooking> bookings;

  const TransportTrips({this.quotes = const [], this.bookings = const []});

  /// Quotes still open: waiting on a provider, or waiting on the customer.
  List<TransportQuote> get openQuotes => quotes
      .where((quote) => !quote.isClosed && !quote.isAccepted)
      .toList(growable: false);

  /// True when there is nothing at all to show — an empty state, not an error.
  /// The customer simply has not used this service yet.
  bool get isEmpty => quotes.isEmpty && bookings.isEmpty;

  /// The next thing worth doing, in one answer: a quoted price the customer can
  /// accept outranks anything still waiting on a provider.
  bool get hasActionableQuote => quotes.any((quote) => quote.canAccept);
}

// ── Tolerant scalar readers ────────────────────────────────────────────────
String _string(Object? raw, {String fallback = ''}) {
  if (raw == null) return fallback;
  final text = raw.toString().trim();
  return text.isEmpty ? fallback : text;
}

bool _bool(Object? raw) {
  if (raw is bool) return raw;
  if (raw is num) return raw != 0;
  if (raw is String) {
    final key = raw.trim().toLowerCase();
    return key == 'true' || key == '1' || key == 'yes';
  }
  return false;
}

double? _double(Object? raw) {
  if (raw == null) return null;
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw.trim());
  return null;
}

int? _int(Object? raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw.trim());
  return null;
}
