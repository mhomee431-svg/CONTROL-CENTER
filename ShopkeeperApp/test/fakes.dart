import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/data/auth_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/domain/auth_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/dashboard/data/dashboard_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/dashboard/domain/dashboard_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/data/product_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/data/shop_repository.dart';

// ---- Fixtures ------------------------------------------------------------

ShopSummary ownerShop({int id = 10, String name = 'Kirana Corner'}) =>
    ShopSummary(
      id: id,
      name: name,
      status: 'REGISTERED',
      isVerified: false,
      category: 'GROCERY',
      membership: 'owner',
      permissions: const ['read:dashboard', 'update:shop'],
    );

ShopSummary managerShop({int id = 20, String name = 'Branch B'}) => ShopSummary(
      id: id,
      name: name,
      status: 'VERIFIED',
      isVerified: true,
      category: 'BAKERY',
      membership: 'manager',
      permissions: const ['read:dashboard', 'update:product'],
    );

AuthSession makeSession({List<ShopSummary>? shops}) => AuthSession(
      user: const ShopkeeperUser(
        id: 1,
        phoneNumber: '+919000000001',
        name: 'Ramesh',
        role: 'shopkeeper',
      ),
      shops: shops ?? [ownerShop()],
    );

Map<String, dynamic> dashboardJson() => {
      'shop': {
        'id': 10,
        'name': 'Kirana Corner',
        'status': 'REGISTERED',
        'is_verified': false,
      },
      'verification': {'status': 'PENDING'},
      'subscription': {'status': 'NONE'},
      'products': {
        'total': 12,
        'active': 9,
        'inactive': 3,
        'in_stock': 7,
        'low_stock': 3,
        'out_of_stock': 2,
        'total_units': 150,
      },
      'recent_updates': [
        {
          'type': 'stock_update',
          'label': 'Basmati Rice stock update',
          'quantity': 25,
        },
        {'type': 'price_update', 'label': 'Sugar 1kg price update'},
      ],
      'offers': {'total': 3, 'active': 1, 'draft': 1},
    };

// ---- Fakes ---------------------------------------------------------------

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.restoreResult, this.submitError, this.sendOtpError});

  AuthSession? restoreResult;
  Object? submitError;
  Object? sendOtpError;

  int otpSends = 0;
  int registerCalls = 0;
  int loginCalls = 0;
  int logoutCalls = 0;
  String? lastRegisteredName;

  @override
  Future<void> sendOtp(String phoneNumber) async {
    if (sendOtpError != null) throw sendOtpError!;
    otpSends++;
  }

  @override
  Future<AuthSession> register({
    required String phoneNumber,
    required String otp,
    required String name,
  }) async {
    registerCalls++;
    lastRegisteredName = name;
    if (submitError != null) throw submitError!;
    return restoreResult ?? makeSession();
  }

  @override
  Future<AuthSession> login({
    required String phoneNumber,
    required String otp,
  }) async {
    loginCalls++;
    if (submitError != null) throw submitError!;
    return restoreResult ?? makeSession();
  }

  @override
  Future<AuthSession?> restoreSession() async => restoreResult;

  @override
  Future<void> logout() async => logoutCalls++;
}

/// Pre-selects a shop so protected routes render in widget tests.
class SelectedShopOverride extends SelectedShopNotifier {
  SelectedShopOverride(this.initial);

  final ShopSummary initial;

  @override
  ShopSummary? build() => initial;
}

class FakeShopRepo implements ShopRepository {
  FakeShopRepo({List<ShopSummary>? shops}) : shops = shops ?? [ownerShop()];

  final List<ShopSummary> shops;
  int registeredShops = 0;
  String? lastRegisteredName;

  @override
  Future<List<ShopSummary>> listMyShops(String token) async => shops;

  @override
  Future<ShopDetail> getShopDetail(int shopId, String token) =>
      throw UnimplementedError();

  @override
  Future<ShopDetail> registerShop(
      Map<String, dynamic> payload, String token) async {
    registeredShops++;
    lastRegisteredName = payload['name'] as String?;
    return ShopDetail(
      summary: ShopSummary(
        id: 99,
        name: lastRegisteredName ?? 'New Shop',
        status: 'REGISTERED',
        isVerified: false,
        membership: 'owner',
        permissions: const [],
      ),
      verification: const VerificationInfo(status: 'PENDING'),
      subscription: const SubscriptionInfo(status: 'NONE'),
      rating: 0,
      reviewCount: 0,
    );
  }

  @override
  Future<void> updateProfile(
          int shopId, Map<String, dynamic> fields, String token) async {}

  @override
  Future<void> updateSettings(
          int shopId, Map<String, dynamic> fields, String token) async {}
}

class FakeDashboardRepo implements DashboardRepository {
  FakeDashboardRepo({this.json, this.error});

  /// Raw payload returned on success.
  final Map<String, dynamic>? json;

  /// When set, thrown instead of returning [json].
  final Object? error;
  int calls = 0;
  int? lastShopId;

  @override
  Future<DashboardData> fetchDashboard(int shopId, String token) async {
    calls++;
    lastShopId = shopId;
    if (error != null) throw error!;
    return DashboardData.fromJson(json ?? dashboardJson());
  }
}

class ForbiddenError implements Exception {}

