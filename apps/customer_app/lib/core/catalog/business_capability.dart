/// What a business may show a customer — the customer-app half of the
/// category-capability model (Master Spec §86-§89).
///
/// WHY THIS EXISTS
/// ---------------
/// A business's category decides which customer-facing surfaces are meaningful:
///
///  * a physical product business — price, stock, distance;
///  * a restaurant — business details, hours, and a DISPLAY-ONLY menu;
///  * a transport / travel provider — service details, availability, contact,
///    location, and a request entry point where the backend supports one.
///
/// Rendering one universal profile and hiding the irrelevant fields with
/// `if (shop.hasProducts)` style guesses is what produces a restaurant page with
/// an empty "Available Products" grid and a stock badge on a taxi service. So the
/// surface is driven by a capability set instead: the screen renders what the
/// business actually offers, and nothing else.
///
/// WHERE THE VALUES COME FROM
/// --------------------------
/// The backend resolves them (`app.models.merchant_category`) and ships them on
/// the shop payload, so a category — or a capability added to one — reaches
/// customers without an app release. The compiled table in
/// `approved_categories.dart` is only a FALLBACK for a payload that carries no
/// capabilities (an older backend, or a response served from the offline cache).
library;

import 'package:flutter/foundation.dart';

import 'approved_categories.dart';

/// One thing a business may expose to the customer.
///
/// Wire names are the contract with the backend and must stay in step with
/// `CustomerCapability` there; they are deliberately lower_snake_case strings
/// rather than an enum index, which would break the moment the backend adds a
/// value.
enum BusinessCapability {
  /// Price + stock + distance listings.
  productCatalog('product_catalog'),

  /// Display-only menu. Never stock, never cart, never checkout.
  menu('menu'),

  /// Service details: a provider's offerings, fleet, or comparable.
  serviceProfile('service_profile'),

  /// Availability information (vehicle counts, availability windows).
  availability('availability'),

  /// The customer may request a quote/booking. Only ever granted where the
  /// backend contract exists, so the button cannot lead to a request that was
  /// never implemented.
  quoteRequest('quote_request'),

  contact('contact'),
  directions('directions'),
  ratings('ratings'),
  offers('offers');

  const BusinessCapability(this.wireName);

  /// The name the backend uses for this capability.
  final String wireName;

  /// Parses one wire value, or null when it is not a capability this build
  /// knows about.
  ///
  /// Unknown values are IGNORED rather than treated as an error: a newer backend
  /// may publish a capability a deployed app has never heard of, and failing the
  /// whole payload over one extra string would break every shop profile at once.
  static BusinessCapability? tryParse(Object? raw) {
    if (raw is! String) return null;
    final key = raw.trim().toLowerCase();
    if (key.isEmpty) return null;
    for (final value in BusinessCapability.values) {
      if (value.wireName == key) return value;
    }
    return null;
  }
}

/// An immutable set of [BusinessCapability], carrying the questions a view
/// actually asks.
///
/// A dedicated type rather than a bare `Set` so that "capabilities were absent"
/// and "capabilities were present and empty" cannot be confused at a call site,
/// and so the fallback decision lives in exactly one place.
@immutable
class BusinessCapabilitySet {
  const BusinessCapabilitySet(this._values);

  final Set<BusinessCapability> _values;

  /// Nothing known — resolves to the product default, see [resolve].
  static const BusinessCapabilitySet empty = BusinessCapabilitySet({});

  /// Parses a backend capability list. Unrecognised entries are dropped; a
  /// malformed payload (not a list) yields [empty] rather than throwing, because
  /// a shop profile must still render with whatever else arrived.
  factory BusinessCapabilitySet.fromWire(Object? raw) {
    if (raw is! List) return empty;
    final parsed = <BusinessCapability>{};
    for (final entry in raw) {
      final capability = BusinessCapability.tryParse(entry);
      if (capability != null) parsed.add(capability);
    }
    return BusinessCapabilitySet(parsed);
  }

  /// The set to render from, deciding between what the backend said and what
  /// this build knows.
  ///
  /// Order matters:
  ///  1. a NON-EMPTY wire list wins — the backend is the source of truth;
  ///  2. otherwise a `Service` business type means a service profile, the only
  ///     signal a service business with an unrecognised category has;
  ///  3. otherwise the compiled category table;
  ///  4. otherwise the product default.
  ///
  /// Step 4 is deliberately the PRODUCT set, not an empty one: the platform's
  /// core promise is product discovery and a physical shop is the common case,
  /// so an unknown category must keep the inventory view rather than blank the
  /// profile. A service business is never reached by step 4, because its
  /// capabilities arrive from the backend (1) or from its business type (2).
  static BusinessCapabilitySet resolve({
    Object? wire,
    String? categoryName,
    String? businessType,
  }) {
    final fromWire = BusinessCapabilitySet.fromWire(wire);
    if (fromWire.isNotEmpty) return fromWire;

    final fromType = businessCapabilitiesForBusinessType(businessType);
    if (fromType != null) return fromType;

    return businessCapabilitiesForCategoryName(categoryName);
  }

  bool get isNotEmpty => _values.isNotEmpty;

  bool get isEmpty => _values.isEmpty;

  bool has(BusinessCapability capability) => _values.contains(capability);

  /// Whether a price/stock/distance inventory surface may be shown.
  bool get supportsProductCatalog => has(BusinessCapability.productCatalog);

  /// Whether a display-only menu may be shown.
  bool get supportsMenu => has(BusinessCapability.menu);

  /// Whether service details (offerings, fleet) may be shown.
  bool get supportsServiceProfile => has(BusinessCapability.serviceProfile);

  /// Whether a request/booking entry point may be shown. True only when the
  /// backend contract for it exists.
  bool get supportsQuoteRequest => has(BusinessCapability.quoteRequest);

  /// Whether the contact actions (call / email) may be shown.
  bool get supportsContact => has(BusinessCapability.contact);

  /// Whether the directions action may be shown.
  bool get supportsDirections => has(BusinessCapability.directions);

  /// True when this business needs a fetched business profile (a menu or a
  /// service profile) rather than the inventory grid.
  bool get needsBusinessProfile => supportsMenu || supportsServiceProfile;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BusinessCapabilitySet && setEquals(_values, other._values);

  @override
  int get hashCode => Object.hashAllUnordered(_values);

  @override
  String toString() => 'BusinessCapabilitySet($_values)';
}

/// The fallback capabilities for a known canonical category name, or the product
/// default when the name is unknown.
BusinessCapabilitySet businessCapabilitiesForCategoryName(
  String? categoryName,
) {
  final category = categoryName == null
      ? null
      : ApprovedCategories.find(categoryName.trim());
  if (category == null) return productBusinessCapabilities;
  final parsed = <BusinessCapability>{};
  for (final name in category.capabilities) {
    final capability = BusinessCapability.tryParse(name);
    if (capability != null) parsed.add(capability);
  }
  return BusinessCapabilitySet(parsed);
}

/// The capabilities implied by the free-form `business_type` ("Service"), or
/// null when it says nothing about the surface.
///
/// A "Service" business gets the service profile but NOT
/// [BusinessCapability.quoteRequest]: a request entry point is only offered when
/// a provider record exists behind it (transport / personal travel), and a form
/// with nothing behind it would be a faked booking.
BusinessCapabilitySet? businessCapabilitiesForBusinessType(
  String? businessType,
) {
  if (businessType == null) return null;
  if (businessType.trim().toLowerCase() != 'service') return null;
  return serviceBusinessCapabilities;
}

/// The default for a physical product business.
const BusinessCapabilitySet productBusinessCapabilities = BusinessCapabilitySet(
  {
    BusinessCapability.productCatalog,
    BusinessCapability.availability,
    BusinessCapability.contact,
    BusinessCapability.directions,
    BusinessCapability.ratings,
    BusinessCapability.offers,
  },
);

/// A generic service business: a profile and contact, no booking promise.
const BusinessCapabilitySet serviceBusinessCapabilities = BusinessCapabilitySet(
  {
    BusinessCapability.serviceProfile,
    BusinessCapability.availability,
    BusinessCapability.contact,
    BusinessCapability.directions,
    BusinessCapability.ratings,
    BusinessCapability.offers,
  },
);
