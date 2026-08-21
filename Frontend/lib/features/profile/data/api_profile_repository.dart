import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../domain/models/user_profile.dart';

/// Real backend implementation for fetching/updating the user profile.
class ApiProfileRepository {
  final ApiClient _apiClient;

  ApiProfileRepository(this._apiClient);

  Future<UserProfile> getProfile() async {
    final data = await _apiClient.get(ApiEndpoints.profile);
    if (data is Map<String, dynamic>) {
      return UserProfile(
        id: data['id']?.toString() ?? '',
        name: data['name']?.toString() ?? '',
        email: data['email']?.toString() ?? '',
        phoneNumber: data['phone_number']?.toString() ?? '',
        avatarUrl: data['avatar_url']?.toString(),
      );
    }
    throw Exception('Invalid profile response');
  }

  Future<UserProfile> updateProfile({
    required String name,
    required String email,
    required String phoneNumber,
  }) async {
    final data = await _apiClient.put(
      ApiEndpoints.profile,
      data: {'name': name, 'email': email},
    );
    if (data is Map<String, dynamic>) {
      return UserProfile(
        id: data['id']?.toString() ?? '',
        name: data['name']?.toString() ?? '',
        email: data['email']?.toString() ?? '',
        phoneNumber: data['phone_number']?.toString() ?? '',
        avatarUrl: data['avatar_url']?.toString(),
      );
    }
    throw Exception('Invalid profile update response');
  }
}