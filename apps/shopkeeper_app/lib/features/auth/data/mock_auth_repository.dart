import '../domain/auth_models.dart';
import 'auth_repository.dart';
import '../../../core/network/token_store.dart';
import '../../../core/network/api_client.dart';

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

  @override
  Future<AuthSession> firebaseLogin({
    required String firebaseIdToken,
    String? name,
    String? email,
    String? photoUrl,
  }) async {
    // Simulate network delay.
    await Future.delayed(const Duration(seconds: 1));
    if (firebaseIdToken.isEmpty) {
      throw const ApiException(message: 'Invalid Firebase token');
    }
    final user = ShopkeeperUser(
      id: 1,
      phoneNumber: '',
      name: name ?? 'Test Shopkeeper',
      email: email,
      avatarUrl: photoUrl,
      role: 'owner',
    );
    await _tokens.saveTokens(
      accessToken: 'mock_access_token_${DateTime.now().millisecondsSinceEpoch}',
      refreshToken: 'mock_refresh_token_${DateTime.now().millisecondsSinceEpoch}',
    );
    return AuthSession(user: user, shops: const []);
  }

  @override
  Future<AuthSession> loginWithPhoneOtp({
    required String firebaseIdToken,
  }) {
    // Offline-dev parity with ApiAuthRepository: OTP reuses the Google
    // exchange because both providers yield the same Firebase ID token.
    return firebaseLogin(firebaseIdToken: firebaseIdToken);
  }

  @override
  Future<AuthSession> createProfile({required String name}) async {
    // Simulate network delay, then return the (mock) refreshed session.
    await Future.delayed(const Duration(seconds: 1));
    final session = await restoreSession();
    return session ??
        AuthSession(
          user: ShopkeeperUser(
            id: 1,
            name: name,
            phoneNumber: '',
            role: 'owner',
          ),
          shops: const [],
        );
  }

  @override
  Future<Map<String, dynamic>> fetchGoogleProfile() async {
    return {
      'name': 'Test Shopkeeper',
      'email': 'test@hyperlocal.app',
      'picture': null,
      'email_verified': true,
      'provider': 'google.com',
      'required_scopes': ['openid', 'email', 'profile'],
    };
  }

  // ── Debug helpers for verbose login flow logging ──────────────────────

  @override
  Future<String?> debugReadToken() async {
    return _tokens.readAccessToken();
  }

  @override
  Future<String?> debugReadUserId() async {
    return _tokens.readUserId();
  }

  @override
  Future<bool> debugIsLoggedIn() async {
    return _tokens.isLoggedIn();
  }
}