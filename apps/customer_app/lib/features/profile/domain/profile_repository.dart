import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/env/env_config.dart';
import '../../../../core/network/api_client.dart';
import '../data/api_profile_repository.dart';
import '../data/mock_profile_repository.dart';
import 'models/user_profile.dart';

/// Selects the profile data source:
///  - Authenticated **and** backend configured -> live API repository.
///  - Otherwise -> local mock, keeping the account area fully usable
///    before backend services ship.
///
/// Watching auth means dependent notifiers reload on login/logout.
final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  // Staging/production always resolve to the live API (per the build-time
  // environment profile); the mock is strictly a development fallback so a
  // mock can never leak into a production build.
  if (EnvConfig.hasApiBaseUrl) {
    return ApiProfileRepository(ref.watch(apiClientProvider));
  }
  return MockProfileRepository();
});

/// Abstract contract for the profile repository.
/// Implementations: [ApiProfileRepository] (backend) and
/// [MockProfileRepository] (testing/development).
abstract class ProfileRepository {
  Future<UserProfile> getProfile();
  Future<UserProfile> updateProfile({
    required String name,
    required String email,
    required String phoneNumber,
  });

  /// Requests deletion of the customer's account.
  ///
  /// Preparation for the backend `DELETE /users/me` endpoint; mock
  /// implementations record the request locally so the flow can be built
  /// and tested before the service ships.
  Future<void> deleteAccount();
}
