import 'package:hyperlocal_shopkeeper_app/core/auth/firebase_auth_service.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/data/auth_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/domain/auth_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/barcode/data/barcode_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/barcode/domain/barcode_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/dashboard/data/dashboard_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/dashboard/domain/dashboard_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/notifications/data/notifications_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/data/import_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/domain/import_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/notifications/domain/notification_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/data/shop_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/domain/shop_models.dart';

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

/// Active shopkeeper with a profile (ready for the Dashboard).
AuthSession makeSession({List<ShopSummary>? shops}) => AuthSession(
  user: const ShopkeeperUser(
    id: 1,
    phoneNumber: '+919000000001',
    name: 'Ramesh',
    status: 'ACTIVE',
    role: 'shopkeeper',
    businessId: 'SHOP_919000000001',
  ),
  shops: shops ?? [ownerShop()],
);

/// Shopkeeper with NO profile (first sign-in → Create Profile).
AuthSession makeEmptyProfileSession() => AuthSession(
  user: const ShopkeeperUser(
    id: 2,
    phoneNumber: '+919000000002',
    name: 'New Shopkeeper',
    status: 'ACTIVE',
    role: 'shopkeeper',
    businessId: 'SHOP_919000000002',
  ),
  shops: const [],
);

/// Suspended/banned/inactive shopkeeper (startup → account-status gate).
/// The [status] param lets tests exercise SUSPENDED / BANNED / INACTIVE.
AuthSession makeRestrictedSession({String status = 'SUSPENDED'}) => AuthSession(
  user: ShopkeeperUser(
    id: 3,
    phoneNumber: '+919000000003',
    name: 'Restricted User',
    status: status,
    role: 'shopkeeper',
    businessId: 'SHOP_919000000003',
  ),
  shops: [ownerShop(id: 99)],
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
  FakeAuthRepository({this.restoreResult, this.submitError});

  AuthSession? restoreResult;
  Object? submitError;

  /// Optional token store so [logout] can mirror the real
  /// ApiAuthRepository contract: the device token store is wiped when the
  /// sign-out completes (even when the server-side revocation fails).
  TokenStore? tokens;

  /// When set, thrown by [logout] ONLY — lets tests fail the server-side
  /// session revoke without breaking [restoreSession]/[firebaseLogin].
  Object? logoutError;

  int firebaseLoginCalls = 0;
  int logoutCalls = 0;
  String? lastRegisteredName;

  String? lastPhotoUrl;

  @override
  Future<AuthSession> firebaseLogin({
    required String firebaseIdToken,
    String? name,
    String? email,
    String? photoUrl,
  }) async {
    firebaseLoginCalls++;
    lastRegisteredName = name;
    lastPhotoUrl = photoUrl;
    if (submitError != null) throw submitError!;
    // A successful sign-in persists a session — model that so a later
    // restoreSession() finds it (same as the real ApiAuthRepository flow).
    return restoreResult ??= makeSession();
  }

  @override
  Future<AuthSession> registerWithPassword({
    required String name,
    required String phoneNumber,
    required String password,
  }) async {
    lastRegisteredName = name;
    if (submitError != null) throw submitError!;
    return restoreResult ?? makeSession();
  }

  @override
  Future<AuthSession> loginWithPassword({
    required String identifier,
    required String password,
  }) async {
    if (submitError != null) throw submitError!;
    return restoreResult ?? makeSession();
  }

  @override
  Future<AuthSession?> restoreSession() async {
    if (submitError != null) throw submitError!;
    return restoreResult;
  }

  @override
  Future<Map<String, dynamic>> fetchGoogleProfile() async {
    return {
      'name': lastRegisteredName ?? 'Home',
      'email': 'home91334@gmail.com',
      'picture': null,
      'email_verified': true,
      'provider': 'google.com',
      'required_scopes': ['openid', 'email', 'profile'],
    };
  }

  @override
  Future<void> forgotPassword(String identifier) async {}

  @override
  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {}

  @override
  Future<AuthSession> updateProfile({
    required String name,
    String? phoneNumber,
  }) async {
    lastRegisteredName = name;
    if (submitError != null) throw submitError!;
    return restoreResult ?? makeSession();
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
    try {
      if (logoutError != null) throw logoutError!;
    } finally {
      // Mirror the real ApiAuthRepository: the device token store is wiped
      // even when the server-side revocation fails.
      await tokens?.clearAll();
    }
  }

  // ── Debug helpers for verbose login flow logging ──────────────────────

  @override
  Future<String?> debugReadToken() async => null;

  @override
  Future<String?> debugReadUserId() async => null;

  @override
  Future<bool> debugIsLoggedIn() async => false;
}

/// Pre-selects a shop so protected routes render in widget tests.
class SelectedShopOverride extends SelectedShopNotifier {
  SelectedShopOverride(this.initial);

  final ShopSummary? initial;

  @override
  ShopSummary? build() => initial;
}

/// Fake Firebase auth service for tests — the real [FirebaseAuthService]
/// touches a platform channel that is unavailable in the test VM, which
/// makes [signOut] hang. This fake overrides the problematic methods.
class FakeFirebaseAuthService extends FirebaseAuthService {
  FakeFirebaseAuthService();

  @override
  Future<void> signOut() async {
    // No-op — avoid the platform channel call that hangs in tests.
  }
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
    Map<String, dynamic> payload,
    String token,
  ) async {
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
    int shopId,
    Map<String, dynamic> fields,
    String token,
  ) async {}

  @override
  Future<void> updateSettings(
    int shopId,
    Map<String, dynamic> fields,
    String token,
  ) async {}

  @override
  Future<Map<String, dynamic>> updateShopLocation(
    int shopId,
    Map<String, dynamic> payload,
    String token,
  ) async {
    return {
      'latitude': payload['latitude'],
      'longitude': payload['longitude'],
      'accuracy_meters': payload['location']?['accuracy_meters'],
      'location_status': 'CORRECTED',
    };
  }

  @override
  Future<List<MerchantCategoryOption>> listMerchantCategories(
    String token,
  ) async => [
    MerchantCategoryOption(
      code: 'PHARMACY_HEALTHCARE',
      name: 'Pharmacy & Healthcare',
    ),
  ];

  @override
  Future<CategoryRequirements> getCategoryRequirements(
    String token,
    String categoryCode,
  ) async {
    return const CategoryRequirements(
      categoryCode: 'PHARMACY_HEALTHCARE',
      categoryName: 'Pharmacy & Healthcare',
      documents: [],
    );
  }

  @override
  Future<void> addShopDocument({
    required int shopId,
    required String documentType,
    required String documentUrl,
    String? documentNumber,
    required String token,
  }) async {}

  @override
  Future<void> updateOperatingHours({
    required int shopId,
    required String openTime,
    required String closeTime,
    required String token,
  }) async {}
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

// ---- Barcode feature fakes -------------------------------------------------

BarcodeResolution foundResolution({String barcode = '8901234567890'}) =>
    BarcodeResolution(
      status: BarcodeResolutionStatus.found,
      barcode: barcode,
      barcodeType: 'EAN-13',
      matches: const [
        CatalogProductMatch(
          productMasterId: 101,
          name: 'Aashirvaad Salt 1kg',
          isAvailableInCatalog: true,
          matchType: 'IDENTIFIER',
        ),
      ],
    );

class FakeBarcodeRepo implements BarcodeRepository {
  FakeBarcodeRepo({this.onResolve, this.onSave, this.error});

  /// When set, returned for every resolve call.
  final BarcodeResolution? onResolve;

  /// When set, thrown from every resolve call (simulates a network failure).
  final Object? error;

  final Future<ShopProductItem> Function(BarcodeSavePayload)? onSave;
  String? lastBarcode;
  int? lastShopId;
  BarcodeSavePayload? lastPayload;

  @override
  Future<BarcodeResolution> resolveBarcode(
    String barcode,
    int? shopId,
    String token,
  ) async {
    lastBarcode = barcode;
    lastShopId = shopId;
    if (error != null) throw error!;
    if (onResolve != null) return onResolve!;
    return foundResolution(barcode: barcode);
  }

  @override
  Future<ShopProductItem> saveFromBarcode(
    int shopId,
    BarcodeSavePayload payload,
    String token,
  ) async {
    lastShopId = shopId;
    lastPayload = payload;
    if (onSave != null) return onSave!(payload);
    return ShopProductItem(
      id: 1,
      name: 'Aashirvaad 1kg',
      status: 'ACTIVE',
      price: payload.price,
      mrp: payload.mrp,
      isActive: payload.publish,
      isAvailable: payload.publish,
      quantity: payload.quantity,
      stockStatus: 'IN_STOCK',
    );
  }
}

// ---- Notifications fakes ------------------------------------------------------------

class FakeNotificationsRepo implements NotificationsRepository {
  FakeNotificationsRepo({this.page, this.error, this.markAsReadError});

  /// Notifications page returned on success.
  final NotificationsPage? page;

  /// When set, thrown by [fetchNotifications].
  final Object? error;

  /// When set, markAsRead throws this error.
  final Object? markAsReadError;

  final List<int> markedRead = [];
  int fetchCalls = 0;

  @override
  Future<NotificationsPage> fetchNotifications(
    int shopId,
    String token, {
    int limit = 50,
  }) async {
    fetchCalls++;
    if (error != null) throw error!;
    return page ?? const NotificationsPage(items: [], unreadCount: 0);
  }

  @override
  Future<void> markAsRead(int notificationId, String token) async {
    if (markAsReadError != null) throw markAsReadError!;
    markedRead.add(notificationId);
  }
}

// ---- Inventory import fakes ------------------------------------------------

class FakeImportRepo implements InventoryImportRepository {
  FakeImportRepo({this.onUpload, this.onConfirm, this.onList, this.error});

  /// When set, returned from upload/preview list calls.
  final ImportPreview? onUpload;
  final ImportConfirmResult? onConfirm;
  final List<ImportJob>? onList;

  /// When set, thrown from every call (simulates a network failure).
  final Object? error;

  int uploadCalls = 0;
  int confirmCalls = 0;
  int? lastShopId;
  PickedWorkbook? lastWorkbook;

  @override
  Future<ImportPreview> upload(
    int shopId,
    PickedWorkbook workbook,
    String token,
  ) async {
    uploadCalls++;
    lastShopId = shopId;
    lastWorkbook = workbook;
    if (error != null) throw error!;
    return onUpload ??
        ImportPreview(
          meta: ImportJob(
            id: 1,
            filename: workbook.name,
            status: 'VALIDATED',
            totalRows: 10,
            validRows: 8,
            errorRows: 2,
          ),
        );
  }

  @override
  Future<ImportPreview> preview(int shopId, int jobId, String token) async {
    if (error != null) throw error!;
    return onUpload ??
        ImportPreview(
          meta: ImportJob(
            id: jobId,
            filename: 'test.xlsx',
            status: 'VALIDATED',
            totalRows: 10,
            validRows: 8,
            errorRows: 2,
          ),
        );
  }

  @override
  Future<ImportConfirmResult> confirm(
    int shopId,
    int jobId,
    String token,
  ) async {
    confirmCalls++;
    lastShopId = shopId;
    if (error != null) throw error!;
    return onConfirm ?? const ImportConfirmResult(processed: 8, failed: 2);
  }

  @override
  Future<List<ImportJob>> listJobs(
    int shopId,
    String token, {
    int limit = 20,
  }) async {
    lastShopId = shopId;
    if (error != null) throw error!;
    return onList ??
        const [
          ImportJob(
            id: 1,
            filename: 'last.xlsx',
            status: 'COMPLETED',
            totalRows: 5,
            validRows: 5,
            errorRows: 0,
          ),
        ];
  }
}
