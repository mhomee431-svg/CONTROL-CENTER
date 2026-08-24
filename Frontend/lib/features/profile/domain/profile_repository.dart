import 'models/user_profile.dart';

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