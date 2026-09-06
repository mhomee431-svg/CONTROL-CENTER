import 'package:dio/dio.dart';
import 'map_providers_config.dart';

class GeoAddress {
  const GeoAddress({required this.formattedAddress, this.city, this.state, this.pincode, this.latitude, this.longitude, this.provider});
  final String formattedAddress;
  final String? city;
  final String? state;
  final String? pincode;
  final double? latitude;
  final double? longitude;
  final String? provider;
}

class GeocodingService {
  GeocodingService._();
  static final GeocodingService instance = GeocodingService._();
  final Dio _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 8)));

  Future<GeoAddress?> reverseGeocode(double lat, double lng) async {
    if (MapProvidersConfig.googleMapsEnabled) { final r = await _googleReverse(lat, lng); if (r != null) return r; }
    if (MapProvidersConfig.mapplsEnabled) { final r = await _mapplsReverse(lat, lng); if (r != null) return r; }
    return _osmReverse(lat, lng);
  }

  Future<GeoAddress?> _googleReverse(double lat, double lng) async {
    try {
      final resp = await _dio.get('https://maps.googleapis.com/maps/api/geocode/json', queryParameters: {'latlng': '$lat,$lng', 'key': MapProvidersConfig.googleMapsApiKey});
      if (resp.data?['status'] != 'OK') return null;
      final results = resp.data!['results'] as List?;
      if (results == null || results.isEmpty) return null;
      return _parseGoogle(results[0] as Map<String, dynamic>);
    } catch (_) { return null; }
  }

  GeoAddress? _parseGoogle(Map<String, dynamic> result) {
    final components = (result['address_components'] as List?) ?? [];
    String? city, state, pincode;
    for (final comp in components) {
      final types = (comp['types'] as List?) ?? [];
      if (types.contains('locality') && city == null) {
        city = comp['long_name'] as String?;
      } else if (types.contains('administrative_area_level_3') && city == null) { city = comp['long_name'] as String?; }
      if (types.contains('administrative_area_level_1') && state == null) state = comp['long_name'] as String?;
      if (types.contains('postal_code') && pincode == null) pincode = comp['long_name'] as String?;
    }
    return GeoAddress(formattedAddress: result['formatted_address'] as String? ?? '', city: city, state: state, pincode: pincode, latitude: (result['geometry']?['location']?['lat'] as num?)?.toDouble(), longitude: (result['geometry']?['location']?['lng'] as num?)?.toDouble(), provider: 'google');
  }

  Future<GeoAddress?> _mapplsReverse(double lat, double lng) async {
    try {
      final resp = await _dio.get('https://apis.mappls.com/advancedmaps/v1/${MapProvidersConfig.mapplsApiKey}/rev_geocode/$lat,$lng');
      final results = resp.data?['results'] as List?;
      if (results == null || results.isEmpty) return null;
      final r = results[0] as Map<String, dynamic>;
      return GeoAddress(formattedAddress: (r['formatted_address'] ?? r['address'] ?? '').toString(), city: (r['city'] ?? r['locality'] ?? '').toString(), state: (r['state'] ?? '').toString(), pincode: (r['pincode'] ?? '').toString(), latitude: lat, longitude: lng, provider: 'mappls');
    } catch (_) { return null; }
  }

  Future<GeoAddress?> _osmReverse(double lat, double lng) async {
    try {
      final resp = await _dio.get('https://nominatim.openstreetmap.org/reverse', queryParameters: {'lat': lat.toStringAsFixed(7), 'lon': lng.toStringAsFixed(7), 'format': 'jsonv2', 'addressdetails': '1', 'zoom': 18}, options: Options(headers: {'User-Agent': 'HyperlocalShopkeeperApp/1.0'}));
      final address = resp.data?['address'] as Map<String, dynamic>?;
      if (address == null) return null;
      final parts = <String>[];
      final house = address['house_number']?.toString(); final road = address['road']?.toString(); final neighbourhood = address['neighbourhood']?.toString(); final suburb = address['suburb']?.toString();
      if (house != null && road != null) {
        parts.add('$house, $road');
      } else if (road != null) { parts.add(road); }
      if (neighbourhood != null) { parts.add(neighbourhood); }
      if (suburb != null) { parts.add(suburb); }
      return GeoAddress(formattedAddress: resp.data?['display_name']?.toString() ?? '', city: (address['city'] ?? address['town'] ?? address['village'] ?? address['county'])?.toString(), state: address['state']?.toString(), pincode: address['postcode']?.toString(), latitude: lat, longitude: lng, provider: 'osm');
    } catch (_) { return null; }
  }

  Future<GeoAddress?> forwardGeocode(String address) async {
    if (MapProvidersConfig.googleMapsEnabled) { final r = await _googleForward(address); if (r != null) return r; }
    if (MapProvidersConfig.mapplsEnabled) { final r = await _mapplsForward(address); if (r != null) return r; }
    return _osmForward(address);
  }

  Future<GeoAddress?> _googleForward(String address) async {
    try {
      final resp = await _dio.get('https://maps.googleapis.com/maps/api/geocode/json', queryParameters: {'address': '$address, India', 'key': MapProvidersConfig.googleMapsApiKey});
      if (resp.data?['status'] != 'OK') return null;
      final results = resp.data!['results'] as List?;
      if (results == null || results.isEmpty) return null;
      return _parseGoogle(results[0] as Map<String, dynamic>);
    } catch (_) { return null; }
  }

  Future<GeoAddress?> _mapplsForward(String address) async {
    try {
      final resp = await _dio.get('https://apis.mappls.com/advancedmaps/v1/${MapProvidersConfig.mapplsApiKey}/geo_code', queryParameters: {'addr': '$address, India'});
      final results = resp.data?['results'] as List?;
      if (results == null || results.isEmpty) return null;
      final r = results[0] as Map<String, dynamic>;
      final center = r['center'] as String?;
      final coords = center?.split(',') ?? [];
      return GeoAddress(formattedAddress: (r['formatted_address'] ?? address).toString(), city: (r['city'] ?? '').toString(), state: (r['state'] ?? '').toString(), pincode: (r['pincode'] ?? '').toString(), latitude: coords.length > 1 ? double.tryParse(coords[0]) : null, longitude: coords.length > 1 ? double.tryParse(coords[1]) : null, provider: 'mappls');
    } catch (_) { return null; }
  }

  Future<GeoAddress?> _osmForward(String address) async {
    try {
      final resp = await _dio.get('https://nominatim.openstreetmap.org/search', queryParameters: {'q': '$address, India', 'format': 'jsonv2', 'addressdetails': '1', 'limit': 1}, options: Options(headers: {'User-Agent': 'HyperlocalShopkeeperApp/1.0'}));
      final results = resp.data as List?;
      if (results == null || results.isEmpty) return null;
      final r = results[0] as Map<String, dynamic>;
      return GeoAddress(formattedAddress: r['display_name']?.toString() ?? address, latitude: double.tryParse(r['lat']?.toString() ?? ''), longitude: double.tryParse(r['lon']?.toString() ?? ''), provider: 'osm');
    } catch (_) { return null; }
  }
}
