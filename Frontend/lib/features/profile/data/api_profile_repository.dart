import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../domain/models/user_profile.dart';
import '../domain/profile_repository.dart';

/// Real backend implementation of [ProfileRepository].
class ApiProfileRepository implements ProfileRepository {
  final ApiClient _apiClient;

  ApiProfileRepository(this._apiClient);

  @override
  Future<UserProfile> getProfile() async {
    final data = await _apiClient.get(ApiEndpoints.profile);
    if (data is Map<String, dynamic>) {
      return _fromApi(data);
    }
    throw Exception('Invalid profile response');
  }

  @override
  Future<UserProfile> updateProfile({
    required String name,
    required String email,
    required String phoneNumber,
  }) async {
    final data = await _apiClient.put(
      ApiEndpoints.profile,
      data: {'name': name, 'email': email, 'phone_number': phoneNumber},
    );
    if (data is Map<String, dynamic>) {
      return _fromApi(data);
    }
    throw Exception('Invalid profile update response');
  }

  @override
  Future<void> deleteAccount() async {
    await _apiClient.delete(ApiEndpoints.me);
  }

  UserProfile _fromApi(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phoneNumber: json['phone_number']?.toString() ?? '',
      avatarUrl: json['avatar_url']?.toString(),
      accountStatus:
          AccountStatus.fromApi(json['account_status']?.toString()),
    );
  }
}