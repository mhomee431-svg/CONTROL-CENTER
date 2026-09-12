import 'package:dio/dio.dart';

import 'map_providers_config.dart';
import 'geocoding_service.dart';

class PlaceSuggestion {
  const PlaceSuggestion({
    required this.placeId,
    required this.description,
    this.mainText,
    this.secondaryText,
    this.sessionToken,
  });
  final String placeId;
  final String description;
  final String? mainText;
  final String? secondaryText;

  /// Session token groups autocomplete + details calls for billing
  /// optimization (Google Places billing docs). Client-generated UUID.
  final String? sessionToken;
}

class PlaceAutocompleteService {
  PlaceAutocompleteService._();
  static final PlaceAutocompleteService instance = PlaceAutocompleteService._();
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ),
  );

  Future<List<PlaceSuggestion>> search(
    String query, {
    String? sessionToken,
  }) async {
    if (query.trim().length < 3 || !MapProvidersConfig.googleMapsEnabled) {
      return [];
    }
    try {
      final params = <String, dynamic>{
        'input': query,
        'key': MapProvidersConfig.googleMapsApiKey,
        'components': 'country:in',
        'types': 'address',
      };
      // Session token (re)used across the autocomplete+details sequence.
      if (sessionToken != null && sessionToken.isNotEmpty) {
        params['sessiontoken'] = sessionToken;
      }
      final resp = await _dio.get(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json',
        queryParameters: params,
      );
      if (resp.data?['status'] != 'OK') return [];
      final predictions = (resp.data!['predictions'] as List?) ?? [];
      return predictions.map((p) {
        final m = p as Map<String, dynamic>;
        final structured = m['structured_formatting'] as Map<String, dynamic>?;
        return PlaceSuggestion(
          placeId: (m['place_id'] ?? '').toString(),
          description: (m['description'] ?? '').toString(),
          mainText: structured?['main_text']?.toString(),
          secondaryText: structured?['secondary_text']?.toString(),
          sessionToken: sessionToken,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<GeoAddress?> getPlaceDetails(
    String placeId, {
    String? sessionToken,
  }) async {
    if (!MapProvidersConfig.googleMapsEnabled) return null;
    try {
      final params = <String, dynamic>{
        'place_id': placeId,
        'key': MapProvidersConfig.googleMapsApiKey,
        'fields': 'formatted_address,geometry,address_components',
      };
      // Concluding the session: same token as the preceding autocomplete call.
      if (sessionToken != null && sessionToken.isNotEmpty) {
        params['sessiontoken'] = sessionToken;
      }
      final resp = await _dio.get(
        'https://maps.googleapis.com/maps/api/place/details/json',
        queryParameters: params,
      );
      if (resp.data?['status'] != 'OK') return null;
      final result = resp.data?['result'] as Map<String, dynamic>?;
      if (result == null) return null;
      final components = (result['address_components'] as List?) ?? [];
      String? city, state, pincode;
      for (final comp in components) {
        final types = (comp['types'] as List?) ?? [];
        if (types.contains('locality') && city == null) {
          city = comp['long_name'] as String?;
        } else if (types.contains('administrative_area_level_3') &&
            city == null) {
          city = comp['long_name'] as String?;
        }
        if (types.contains('administrative_area_level_1') && state == null) {
          state = comp['long_name'] as String?;
        }
        if (types.contains('postal_code') && pincode == null) {
          pincode = comp['long_name'] as String?;
        }
      }
      return GeoAddress(
        formattedAddress: result['formatted_address']?.toString() ?? '',
        city: city,
        state: state,
        pincode: pincode,
        latitude: (result['geometry']?['location']?['lat'] as num?)?.toDouble(),
        longitude: (result['geometry']?['location']?['lng'] as num?)
            ?.toDouble(),
        provider: 'google',
      );
    } catch (_) {
      return null;
    }
  }
}
