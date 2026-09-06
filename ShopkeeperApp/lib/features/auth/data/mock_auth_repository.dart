import '../domain/auth_models.dart';
import 'auth_repository.dart';
import '../../../../core/network/token_store.dart';
import '../../../../core/network/api_client.dart';

/// Mock auth repository for testing without backend.
/// Simulates the OTP flow without making real API calls.
/// The OTP is always 123456 for easy testing.
class MockAuthRepository implements AuthRepository {
  MockAuthRepository(this._tokens);

  final TokenStore _tokens;

  /// The mock OTP code. Always 123456 so testers can sign in instantly.
  static const String mockOtp = '123456';

  @override
  Future<AuthSession> registerWithFirebase({
    required String phoneNumber,
    required String firebaseIdToken,
    required String name,
    String? password,
  }) async {
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 1));

    // Create mock session
    final user = ShopkeeperUser(
      id: 1,
      phoneNumber: phoneNumber,
      name: name,
      email: null,
      role: 'owner',
    );

    final shops = <ShopSummary>[];

    // Save mock tokens
    await _tokens.saveTokens(
      accessToken: 'mock_access_token_${DateTime.now().millisecondsSinceEpoch}',
      refreshToken: 'mock_refresh_token_${DateTime.now().millisecondsSinceEpoch}',
    );

    return AuthSession(user: user, shops: shops);
  }

  @override
  Future<AuthSession> loginWithFirebase({
    required String firebaseIdToken,
  }) async {
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 1));

    // Create mock session
    final user = ShopkeeperUser(
      id: 1,
      phoneNumber: '+919999999999',
      name: 'Test Shopkeeper',
      email: null,
      role: 'owner',
    );

    final shops = <ShopSummary>[];

    // Save mock tokens
    await _tokens.saveTokens(
      accessToken: 'mock_access_token_${DateTime.now().millisecondsSinceEpoch}',
      refreshToken: 'mock_refresh_token_${DateTime.now().millisecondsSinceEpoch}',
    );

    return AuthSession(user: user, shops: shops);
  }

  @override
  Future<AuthSession> loginWithFirebaseAuto({
    required String firebaseIdToken,
    String? name,
  }) async {
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 1));

    // Auto-register / login — mock users always exist
    final user = ShopkeeperUser(
      id: 1,
      phoneNumber: '+919999999999',
      name: name ?? 'Test Shopkeeper',
      email: null,
      role: 'owner',
    );

    final shops = <ShopSummary>[];

    await _tokens.saveTokens(
      accessToken: 'mock_access_token_${DateTime.now().millisecondsSinceEpoch}',
      refreshToken: 'mock_refresh_token_${DateTime.now().millisecondsSinceEpoch}',
    );

    return AuthSession(user: user, shops: shops);
  }

  @override
  Future<AuthSession> loginWithPassword({
    required String identifier,
    required String password,
  }) async {
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 1));

    // Accept any non-empty password for testing
    if (password.isEmpty) {
      throw const ApiException(message: 'Invalid credentials');
    }

    final user = ShopkeeperUser(
      id: 1,
      phoneNumber: '+919999999999',
      name: 'Test Shopkeeper',
      email: identifier.contains('@') ? identifier : null,
      role: 'owner',
    );

    final shops = <ShopSummary>[];

    await _tokens.saveTokens(
      accessToken: 'mock_access_token_${DateTime.now().millisecondsSinceEpoch}',
      refreshToken: 'mock_refresh_token_${DateTime.now().millisecondsSinceEpoch}',
    );

    return AuthSession(user: user, shops: shops);
  }

  @override
  Future<void> forgotPassword(String identifier) async {
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 1));
    // Mock always succeeds
  }

  @override
  Future<void> resetPassword({required String token, required String newPassword}) async {
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 1));
    if (token.isEmpty) {
      throw const ApiException(message: 'Invalid or expired reset token');
    }
  }

  @override
  Future<AuthSession?> restoreSession() async {
    final access = await _tokens.readAccessToken();
    if (access == null || access.isEmpty) return null;

    // If we have a mock token, return mock session
    if (access.startsWith('mock_access_token_')) {
      return const AuthSession(
        user: ShopkeeperUser(
          id: 1,
          phoneNumber: '+919999999999',
          name: 'Test Shopkeeper',
          email: null,
          role: 'owner',
        ),
        shops: [],
      );
    }

    return null;
  }

  @override
  Future<void> logout() async {
    await _tokens.clearAll();
  }
}
