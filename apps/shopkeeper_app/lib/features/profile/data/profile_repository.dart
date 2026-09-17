import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/token_store.dart';

/// The signed-in shopkeeper's own profile (identity, not shop data).
///
/// Backend contract: `GET/PUT /api/v1/profile` (IDOR-safe — the user is
/// derived from the verified token, never from client input; PUT applies a
/// PARTIAL update: omitted/`null` fields are left unchanged).
class UserProfile {
  const UserProfile({
    required this.id,
    required this.phoneNumber,
    this.name,
    this.email,
    this.avatarUrl,
  });

  final int id;
  final String phoneNumber;
  final String? name;
  final String? email;
  final String? avatarUrl;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: (json['id'] as num?)?.toInt() ?? 0,
        phoneNumber: json['phone_number'] as String? ?? '',
        name: json['name'] as String?,
        email: json['email'] as String?,
        avatarUrl: json['avatar_url'] as String?,
      );
}

/// Reads and updates the shopkeeper's own profile.
class ProfileRepository {
  ProfileRepository(this._api, this._tokens);

  final ApiClient _api;
  final TokenStore _tokens;

  Future<UserProfile> fetchProfile() async {
    final token = await _tokens.readAccessToken();
    final data = await _api.get(ApiEndpoints.profile, token: token)
        as Map<String, dynamic>;
    return UserProfile.fromJson(data);
  }

  /// Partial update — only non-null arguments are sent, so omitted fields
  /// stay unchanged on the backend (its PUT semantics).
  Future<UserProfile> updateProfile({String? name, String? email}) async {
    final token = await _tokens.readAccessToken();
    final data = await _api.put(
      ApiEndpoints.profile,
      body: {
        'name': ?name,
        'email': ?email,
      },
      token: token,
    ) as Map<String, dynamic>;
    return UserProfile.fromJson(data);
  }
}
