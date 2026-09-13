import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_providers.dart';

/// Result of a pincode lookup.
class PincodeResult {
  const PincodeResult({required this.city, required this.state});
  final String city;
  final String state;
}

/// City / state lookup by pincode (live via backend -> PostPin / Google Maps).
abstract class LookupRepository {
  Future<PincodeResult?> lookupPincode(String pincode);
}

class ApiLookupRepository implements LookupRepository {
  ApiLookupRepository(this._api);

  final ApiClient _api;

  @override
  Future<PincodeResult?> lookupPincode(String pincode) async {
    try {
      final data = await _api.get(ApiEndpoints.pincode(pincode))
          as Map<String, dynamic>;
      final city = (data['city'] as String?)?.trim() ?? '';
      final state = (data['state'] as String?)?.trim() ?? '';
      if (city.isEmpty || state.isEmpty) return null;
      return PincodeResult(city: city, state: state);
    } catch (_) {
      return null; // let the caller keep manual entry
    }
  }
}

final lookupRepositoryProvider = Provider<LookupRepository>((ref) {
  final api = ref.watch(apiClientProvider);
  return ApiLookupRepository(api);
});
