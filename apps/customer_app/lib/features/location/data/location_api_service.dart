import 'package:dio/dio.dart';

import '../domain/models/map_route.dart';

/// Location data returned from the backend /locations/nearby endpoint.
class NearbyShopDto {
  const NearbyShopDto({
    required this.shopId,
    required this.shopName,
    required this.distanceKm,
    required this.latitude,
    required this.longitude,
    this.address,
    this.etaText,
    this.etaSeconds,
  });

  factory NearbyShopDto.fromJson(Map<String, dynamic> json) => NearbyShopDto(
    shopId: json['shop_id'] as int,
    shopName: json['shop_name'] as String,
    distanceKm: (json['distance_km'] as num).toDouble(),
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    address: json['address'] as String?,
    etaText: json['eta_text'] as String?,
    etaSeconds: json['eta_seconds'] as int?,
  );

  final int shopId;
  final String shopName;
  final double distanceKm;
  final double latitude;
  final double longitude;
  final String? address;
  final String? etaText;
  final int? etaSeconds;
}

/// Structured address from reverse geocoding.
class ReverseGeocodeDto {
  const ReverseGeocodeDto({
    required this.formattedAddress,
    this.streetNumber,
    this.route,
    this.locality,
    this.district,
    this.state,
    this.pincode,
    this.country,
    this.latitude,
    this.longitude,
    this.placeId,
  });

  factory ReverseGeocodeDto.fromJson(Map<String, dynamic> json) =>
      ReverseGeocodeDto(
        formattedAddress: json['formatted_address'] as String? ?? '',
        streetNumber: json['street_number'] as String?,
        route: json['route'] as String?,
        locality: json['locality'] as String?,
        district: json['district'] as String?,
        state: json['state'] as String?,
        pincode: json['pincode'] as String?,
        country: json['country'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        placeId: json['place_id'] as String?,
      );

  final String formattedAddress;
  final String? streetNumber;
  final String? route;
  final String? locality;
  final String? district;
  final String? state;
  final String? pincode;
  final String? country;
  final double? latitude;
  final double? longitude;
  final String? placeId;
}

/// Autocomplete suggestion from Places API.
class AutocompleteSuggestionDto {
  const AutocompleteSuggestionDto({
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
    this.types = const [],
  });

  factory AutocompleteSuggestionDto.fromJson(Map<String, dynamic> json) =>
      AutocompleteSuggestionDto(
        placeId: json['place_id'] as String? ?? '',
        mainText: json['main_text'] as String? ?? '',
        secondaryText: json['secondary_text'] as String? ?? '',
        types: (json['types'] as List?)?.cast<String>() ?? const [],
      );

  final String placeId;
  final String mainText;
  final String secondaryText;
  final List<String> types;
}

/// Route and ETA from Directions API.
class DirectionsDto {
  const DirectionsDto({
    required this.distanceMeters,
    required this.distanceText,
    required this.durationSeconds,
    required this.durationText,
    this.polyline,
    required this.startAddress,
    required this.endAddress,
  });

  factory DirectionsDto.fromJson(Map<String, dynamic> json) => DirectionsDto(
    distanceMeters: json['distance_meters'] as int? ?? 0,
    distanceText: json['distance_text'] as String? ?? '',
    durationSeconds: json['duration_seconds'] as int? ?? 0,
    durationText: json['duration_text'] as String? ?? '',
    polyline: json['polyline'] as String?,
    startAddress: json['start_address'] as String? ?? '',
    endAddress: json['end_address'] as String? ?? '',
  );

  MapRoute? toMapRoute() {
    if (polyline == null) return null;
    return MapRoute(
      points: [],
      distanceKm: distanceMeters / 1000.0,
      durationMinutes: durationSeconds / 60.0,
      encodedPolyline: polyline!,
    );
  }

  final int distanceMeters;
  final String distanceText;
  final int durationSeconds;
  final String durationText;
  final String? polyline;
  final String startAddress;
  final String endAddress;
}

/// API service for location endpoints.
class LocationApiService {
  LocationApiService(this._dio);

  final Dio _dio;

  Future<List<NearbyShopDto>> getNearbyShops({
    required double latitude,
    required double longitude,
    double radiusKm = 5.0,
    bool includeEta = false,
  }) async {
    final resp = await _dio.get(
      '/locations/nearby',
      queryParameters: {
        'latitude': latitude,
        'longitude': longitude,
        'radius_km': radiusKm,
        'include_eta': includeEta,
      },
    );
    final data = resp.data['data'] as Map<String, dynamic>;
    final shops = data['shops'] as List;
    return shops
        .map((s) => NearbyShopDto.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  Future<ReverseGeocodeDto?> reverseGeocode(
    double latitude,
    double longitude,
  ) async {
    final resp = await _dio.get(
      '/locations/reverse-geocode',
      queryParameters: {'latitude': latitude, 'longitude': longitude},
    );
    final data = resp.data['data'] as Map<String, dynamic>?;
    if (data == null) return null;
    return ReverseGeocodeDto.fromJson(data);
  }

  Future<List<AutocompleteSuggestionDto>> autocomplete(
    String query, {
    double? latitude,
    double? longitude,
    int radius = 50000,
  }) async {
    final params = <String, dynamic>{'q': query, 'radius': radius};
    if (latitude != null && longitude != null) {
      params['latitude'] = latitude;
      params['longitude'] = longitude;
    }
    final resp = await _dio.get(
      '/locations/autocomplete',
      queryParameters: params,
    );
    final data = resp.data['data'] as Map<String, dynamic>;
    final suggestions = data['suggestions'] as List;
    return suggestions
        .map(
          (s) => AutocompleteSuggestionDto.fromJson(s as Map<String, dynamic>),
        )
        .toList();
  }

  Future<DirectionsDto?> getDirections({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    String mode = 'driving',
  }) async {
    final resp = await _dio.get(
      '/locations/directions',
      queryParameters: {
        'origin_lat': originLat,
        'origin_lng': originLng,
        'dest_lat': destLat,
        'dest_lng': destLng,
        'mode': mode,
      },
    );
    final data = resp.data['data'] as Map<String, dynamic>?;
    if (data == null) return null;
    return DirectionsDto.fromJson(data);
  }

  Future<MapLatLng?> getPlaceCoordinates(String placeId) async {
    final resp = await _dio.get(
      '/locations/place-coordinates',
      queryParameters: {'place_id': placeId},
    );
    final data = resp.data['data'] as Map<String, dynamic>?;
    if (data == null) return null;
    return MapLatLng(
      latitude: (data['latitude'] as num).toDouble(),
      longitude: (data['longitude'] as num).toDouble(),
    );
  }
}
