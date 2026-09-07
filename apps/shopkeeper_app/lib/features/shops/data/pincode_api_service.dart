import 'package:dio/dio.dart';

/// Result of a pincode API lookup (live from India Post / PostPin API).
class PincodeApiResult {
  const PincodeApiResult({
    required this.pincode,
    required this.city,
    required this.state,
    required this.district,
    required this.country,
    this.postOffices = const [],
  });

  final String pincode;
  final String city;
  final String state;
  final String district;
  final String country;
  final List<PostOffice> postOffices;

  factory PincodeApiResult.fromPostPin(List<dynamic> offices) {
    if (offices.isEmpty) {
      return const PincodeApiResult(
        pincode: '',
        city: '',
        state: '',
        district: '',
        country: '',
      );
    }
    final first = offices.first as Map<String, dynamic>;
    return PincodeApiResult(
      pincode: (first['Pincode'] ?? '').toString(),
      city: (first['Region'] ?? first['Division'] ?? '').toString(),
      state: (first['State'] ?? '').toString(),
      district: (first['District'] ?? '').toString(),
      country: (first['Country'] ?? 'India').toString(),
      postOffices: [
        for (final o in offices)
          PostOffice.fromJson(o as Map<String, dynamic>),
      ],
    );
  }
}

class PostOffice {
  const PostOffice({
    required this.name,
    required this.branch,
    required this.district,
    required this.state,
    required this.pincode,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final String branch;
  final String district;
  final String state;
  final String pincode;
  final double? latitude;
  final double? longitude;

  factory PostOffice.fromJson(Map<String, dynamic> json) {
    final lat = json['Latitude'];
    final lng = json['Longitude'];
    return PostOffice(
      name: (json['Name'] ?? '').toString(),
      branch: (json['BranchType'] ?? '').toString(),
      district: (json['District'] ?? '').toString(),
      state: (json['State'] ?? '').toString(),
      pincode: (json['Pincode'] ?? '').toString(),
      latitude: lat != null && lat.toString().trim().isNotEmpty
          ? double.tryParse(lat.toString())
          : null,
      longitude: lng != null && lng.toString().trim().isNotEmpty
          ? double.tryParse(lng.toString())
          : null,
    );
  }
}

/// Live pincode lookup service — calls the PostPin API every time a
/// pincode is entered and resolves the city / state instantly.
class PincodeApiService {
  PincodeApiService._();
  static final PincodeApiService instance = PincodeApiService._();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
    baseUrl: 'https://api.postalpincode.in',
  ));

  /// Look up a 6-digit pincode via PostPin API.
  /// Returns null for invalid / unknown pincodes.
  Future<PincodeApiResult?> lookup(String pincode) async {
    final clean = pincode.trim();
    if (clean.length != 6 || !RegExp(r'^\d{6}$').hasMatch(clean)) {
      return null;
    }
    try {
      final resp = await _dio.get('/pincode/$clean');
      final body = resp.data as List<dynamic>?;
      if (body == null || body.isEmpty) return null;
      final first = body.first as Map<String, dynamic>?;
      if (first == null) return null;
      final status = (first['Status'] ?? '').toString().toLowerCase();
      if (status != 'success') return null;
      final offices = (first['PostOffice'] as List<dynamic>?) ?? const [];
      if (offices.isEmpty) return null;
      return PincodeApiResult.fromPostPin(offices);
    } catch (e) {
      return null; // Fall back to bundled dataset
    }
  }
}
