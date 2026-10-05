import '../../../core/cache/local_cache_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_error_handler.dart';
import '../../../core/network/api_payload_exception.dart';
import '../domain/shop_details_repository.dart';
import '../domain/models/business_profile_models.dart';
import '../domain/models/shop_details_models.dart';

/// Real backend implementation of [ShopDetailsRepository] with local caching
/// for offline resilience. Inventory/availability data is never cached to avoid
/// presenting stale stock as confirmed live stock.
class ApiShopDetailsRepository implements ShopDetailsRepository {
  final ApiClient _apiClient;
  final LocalCacheService _cache;

  static const String _cachePrefix = 'shop_details_';

  ApiShopDetailsRepository(this._apiClient, this._cache);

  @override
  Future<ShopProfile> getShopProfile(String shopId) async {
    try {
      final data = await _apiClient.get(
        ApiEndpoints.shop(shopId),
        requiresAuth: false,
      );

      if (data is Map<String, dynamic>) {
        final products = (data['available_products'] as List<dynamic>? ?? [])
            .map((e) => _mapProduct(e as Map<String, dynamic>))
            .toList();

        // Public contact surface only: the backend exposes primary phone,
        // a public alternate (`secondary_phone`/legacy `whatsapp_number`),
        // and email. Anything else stays server-side.
        final secondaryPhone =
            data['secondary_phone']?.toString() ??
            data['alternate_phone']?.toString() ??
            data['whatsapp_number']?.toString() ??
            '';
        final email =
            data['email']?.toString() ??
            data['contact_email']?.toString() ??
            '';

        // Coordinates only count when they are real numbers in range; the
        // [ShopProfile.hasValidCoordinates] gate keeps map/directions honest.
        final latitude = (data['latitude'] as num?)?.toDouble() ?? 0;
        final longitude = (data['longitude'] as num?)?.toDouble() ?? 0;

        final profile = ShopProfile(
          id: data['id']?.toString() ?? shopId,
          name: data['name']?.toString() ?? '',
          imageUrl: data['image_url']?.toString() ?? '',
          rating: (data['rating'] as num?)?.toDouble() ?? 0,
          reviewCount: (data['review_count'] as num?)?.toInt() ?? 0,
          address: data['address']?.toString() ?? '',
          distanceInKm: (data['distance_km'] as num?)?.toDouble() ?? 0,
          openingHours: data['opening_hours']?.toString() ?? '',
          isOpenNow: data['is_open_now'] == true,
          phone: data['phone']?.toString() ?? '',
          about: data['description']?.toString() ?? '',
          lastInventoryUpdate:
              DateTime.tryParse(
                data['last_inventory_update']?.toString() ?? '',
              ) ??
              DateTime.now(),
          activeOffers: (data['active_offers'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList(),
          availableProducts: products,
          isSaved: data['is_saved'] == true,
          categories: (data['categories'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList(),
          // Business type + capabilities (§86-§89): the backend resolves what
          // this business may show — a restaurant or a service provider never
          // inherits product-style price/stock UI from a client guess. Absent
          // keys keep their defaults; the profile then resolves the fallback.
          capabilities: (data['capabilities'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList(),
          businessCategoryName:
              data['business_category_name']?.toString() ?? '',
          businessCategoryCode:
              data['business_category_code']?.toString() ?? '',
          businessType: data['business_type']?.toString() ?? '',
          isVerified: data['is_verified'] == true,
          latitude: latitude,
          longitude: longitude,
          secondaryPhone: secondaryPhone,
          email: email,
        );

        // Cache shop profile (non-inventory data) for offline use
        final cacheData = Map<String, dynamic>.from(data);
        cacheData.remove('available_products');
        await _cache.put('$_cachePrefix$shopId', cacheData);
        return profile;
      }
      throw Exception('Invalid shop details response');
    } catch (e) {
      // On failure, try to serve cached shop info (without live inventory)
      final cached = await _cache.get('$_cachePrefix$shopId');
      if (cached != null && cached.data is Map<String, dynamic>) {
        final data = cached.data as Map<String, dynamic>;
        return ShopProfile(
          id: data['id']?.toString() ?? shopId,
          name: data['name']?.toString() ?? '',
          imageUrl: data['image_url']?.toString() ?? '',
          rating: (data['rating'] as num?)?.toDouble() ?? 0,
          reviewCount: (data['review_count'] as num?)?.toInt() ?? 0,
          address: data['address']?.toString() ?? '',
          distanceInKm: (data['distance_km'] as num?)?.toDouble() ?? 0,
          openingHours: data['opening_hours']?.toString() ?? '',
          isOpenNow: false,
          phone: data['phone']?.toString() ?? '',
          about: data['description']?.toString() ?? '',
          lastInventoryUpdate: DateTime.now(),
          activeOffers: [],
          availableProducts: [],
          isSaved: data['is_saved'] == true,
          categories: (data['categories'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList(),
          capabilities: (data['capabilities'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList(),
          businessCategoryName:
              data['business_category_name']?.toString() ?? '',
          businessCategoryCode:
              data['business_category_code']?.toString() ?? '',
          businessType: data['business_type']?.toString() ?? '',
          isVerified: data['is_verified'] == true,
          latitude: (data['latitude'] as num?)?.toDouble() ?? 0,
          longitude: (data['longitude'] as num?)?.toDouble() ?? 0,
          secondaryPhone: data['secondary_phone']?.toString() ?? '',
          email: data['email']?.toString() ?? '',
        );
      }
      rethrow;
    }
  }

  ShopProductSummary _mapProduct(Map<String, dynamic> json) {
    return ShopProductSummary(
      productId: json['product_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      imageUrl: json['image_url']?.toString() ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      isAvailable: json['is_available'] == true,
    );
  }

  /// A 404 from a by-shop profile lookup is a NORMAL answer — it means this
  /// shop has no profile of that kind behind it.
  ///
  /// Connectivity-shaped failures let the caller retry; anything else
  /// propagates. In particular a payload that cannot be parsed RETHROWS: hiding
  /// a restaurant's menu or a provider's services would look like a bug to the
  /// customer, while an error state invites a retry.
  ///
  /// The declared return type is the honest one: these lookups only ever read
  /// through the API client, and a 404 answer is filtered here, so a caller can
  /// branch on null without naming an HTTP concept.
  @override
  Future<RestaurantProfile?> getRestaurantProfile(String shopId) async {
    try {
      final data = await _apiClient.get(
        ApiEndpoints.restaurantByShop(shopId),
        requiresAuth: false,
      );
      return RestaurantProfile.tryParse(data);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<TransportServiceProfile?> getTransportServiceProfile(
    String shopId,
  ) async {
    try {
      final data = await _apiClient.get(
        ApiEndpoints.transportProviderByShop(shopId),
        requiresAuth: false,
      );
      return TransportServiceProfile.tryParse(data);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<TransportQuoteReceipt> requestTransportQuote(
    TransportQuoteRequest request,
  ) async {
    final data = await _apiClient.post(
      ApiEndpoints.transportQuotes,
      data: request.toJson(),
    );
    final receipt = TransportQuoteReceipt.tryParse(data);
    if (receipt == null) {
      // The backend acknowledged the request but answered in a shape this build
      // does not recognise. Treating that as success would be lying; the
      // ViewModel reports it as a failure the customer can safely retry.
      throw const ApiPayloadException(
        'transport_quote',
        'Unrecognised confirmation shape from POST ${ApiEndpoints.transportQuotes}',
      );
    }
    return receipt;
  }

  /// The customer's quotes and bookings in one read.
  ///
  /// Two requests rather than one, issued CONCURRENTLY: they are independent, so
  /// a customer with no bookings should not wait on a booking fetch before their
  /// quotes appear. A failure in either surfaces as an error for the whole load —
  /// the trips screen's job is to answer "what is happening with my trip?", and a
  /// half answer (quotes but no bookings) is more confusing than a retry.
  @override
  Future<TransportTrips> getMyTransportTrips() async {
    final results = await Future.wait([
      _apiClient.get(ApiEndpoints.transportQuotes),
      _apiClient.get(ApiEndpoints.transportBookings),
    ]);

    final quotes = <TransportQuote>[];
    for (final entry in _asList(results[0])) {
      final quote = TransportQuote.tryParse(entry);
      if (quote != null) quotes.add(quote);
    }
    final bookings = <TransportBooking>[];
    for (final entry in _asList(results[1])) {
      final booking = TransportBooking.tryParse(entry);
      if (booking != null) bookings.add(booking);
    }
    return TransportTrips(quotes: quotes, bookings: bookings);
  }

  @override
  Future<TransportBooking> acceptTransportQuote(String quoteId) async {
    final data = await _apiClient.post(
      ApiEndpoints.transportAcceptQuote(quoteId),
    );
    return _requireBooking(
      data,
      'Unrecognised booking shape from POST '
      '${ApiEndpoints.transportAcceptQuote(quoteId)}',
    );
  }

  @override
  Future<TransportBooking> cancelTransportBooking(
    String bookingId, {
    String? reason,
  }) async {
    final data = await _apiClient.post(
      ApiEndpoints.transportCancelBooking(bookingId),
      data: {if ((reason ?? '').trim().isNotEmpty) 'reason': reason!.trim()},
    );
    return _requireBooking(
      data,
      'Unrecognised booking shape from POST '
      '${ApiEndpoints.transportCancelBooking(bookingId)}',
    );
  }

  /// A booking the backend confirmed, or an error — never a guess.
  ///
  /// The accept and cancel routes serialize the booking ROW, while the detail
  /// route returns a dict. Both are read here, and a shape this build cannot
  /// read raises a payload error rather than a fabricated booking reference.
  TransportBooking _requireBooking(Object? data, String reason) {
    final raw = data is Map ? data : null;
    final booking = TransportBooking.tryParse(raw);
    if (booking != null) return booking;
    throw ApiPayloadException('transport_booking', reason);
  }

  /// The list inside a response body, tolerating an envelope or a bare list.
  List<dynamic> _asList(Object? data) {
    if (data is List) return data;
    if (data is Map && data['data'] is List) return data['data'] as List;
    return const [];
  }

  @override
  Future<void> toggleSaveShop(String shopId, bool save) async {
    if (save) {
      await _apiClient.post(ApiEndpoints.savedShop(shopId));
    } else {
      await _apiClient.delete(ApiEndpoints.savedShop(shopId));
    }
  }
}
