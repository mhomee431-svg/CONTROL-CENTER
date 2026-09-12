import '../domain/auth_models.dart';
import 'auth_repository.dart';
import '../../../../core/network/token_store.dart';
import '../../../../core/network/api_client.dart';

/// Mock auth repository for offline development / testing (no backend).
class MockAuthRepository implements AuthRepository {
  MockAuthRepository(this._tokens);

  final TokenStore _tokens;

  @override
  Future<AuthSession> registerWithPassword({
    required String name,
    required String phoneNumber,
    required String password,
  }) async {
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 1));

    if (password.isEmpty) {
      throw const ApiException(message: 'Password is required');
    }

    // Create mock session
    final user = ShopkeeperUser(
      id: 1,
      phoneNumber: phoneNumber,
      name: name,
      email: null,
      role: 'owner',
      businessId: 'SHOP_${phoneNumber.replaceAll(RegExp(r'\D'), '')}',
    );

    await _tokens.saveTokens(
      accessToken: 'mock_access_token_${DateTime.now().millisecondsSinceEpoch}',
      refreshToken: 'mock_refresh_token_${DateTime.now().millisecondsSinceEpoch}',
    );
    await _tokens.saveBusinessId(user.businessId!);

    return AuthSession(user: user, shops: const []);
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

    await _tokens.saveTokens(
      accessToken: 'mock_access_token_${DateTime.now().millisecondsSinceEpoch}',
      refreshToken: 'mock_refresh_token_${DateTime.now().millisecondsSinceEpoch}',
    );

    return AuthSession(user: user, shops: const []);
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