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
import 'package:hyperlocal_shopkeeper_app/features/insights/data/insights_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/insights/domain/insights_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/notifications/domain/notification_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/offers/data/offers_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/offers/domain/offer_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/pos/data/pos_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/pos/domain/pos_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/data/product_repository.dart';
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
  Future<AuthSession> loginWithPhoneOtp({
    required String firebaseIdToken,
  }) {
    // FUTURE Phone-OTP seam: same exchange as Google (one Firebase ID-token
    // shape). Counted separately so tests can prove the OTP path routes
    // through the identical /firebase-login contract.
    return firebaseLogin(firebaseIdToken: firebaseIdToken);
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

/// Returns [n] flagged as read, preserving every other field. Mirrors the
/// server-confirmed shape the real backend returns after a mark-as-read.
ShopkeeperNotification _asReadNotification(ShopkeeperNotification n) =>
    ShopkeeperNotification(
      id: n.id,
      title: n.title,
      body: n.body,
      type: n.type,
      isRead: true,
      createdAt: n.createdAt,
      deepLink: n.deepLink,
    );

/// In-memory notifications repository.
///
/// The fake is **stateful with respect to read state**: every id passed to
/// [markAsRead] stays read on all subsequent [fetchNotifications] calls, and
/// the returned `unreadCount` accounts for them. Without this the fake could
/// only ever replay its constructor `page`, so a test that reads a
/// notification and then refetches would see the *original* unread count
/// again — making it impossible to prove the UI tracks server state.
///
/// When nothing has been marked read the base `page` is returned untouched,
/// so existing fixtures (e.g. a page whose `unreadCount` is independent of
/// its `items`) keep their exact previous behaviour.
class FakeNotificationsRepo implements NotificationsRepository {
  FakeNotificationsRepo({this.page, this.error, this.markAsReadError});

  /// Notifications page returned on success (the baseline state).
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
    final base = page ?? const NotificationsPage(items: [], unreadCount: 0);
    if (markedRead.isEmpty) return base;

    // Apply the accumulated read state on top of the baseline page.
    final items = <ShopkeeperNotification>[];
    var consumed = 0;
    for (final n in base.items) {
      if (!markedRead.contains(n.id)) {
        items.add(n);
        continue;
      }
      if (n.isUnread) consumed++;
      items.add(_asReadNotification(n));
    }
    final unread = base.unreadCount - consumed;
    return NotificationsPage(
      items: items,
      unreadCount: unread < 0 ? 0 : unread,
    );
  }

  @override
  Future<void> markAsRead(int notificationId, String token) async {
    if (markAsReadError != null) throw markAsReadError!;
    if (!markedRead.contains(notificationId)) markedRead.add(notificationId);
  }
}

// ---- Offers fakes -----------------------------------------------------------

/// Builds one offer row for the list fixture. Defaults describe a LIVE offer so
/// tests only override the field they are actually exercising.
OfferSummary offerSummary({
  int id = 1,
  String title = 'Monsoon Sale',
  String offerType = 'PERCENTAGE_DISCOUNT',
  String status = 'ACTIVE',
  String? displayStatus,
  double? discountPercentage = 15,
  double? discountValue,
  int productCount = 3,
  DateTime? startDate,
  DateTime? endDate,
}) =>
    OfferSummary(
      id: id,
      title: title,
      offerType: offerType,
      status: status,
      displayStatus: displayStatus ?? status,
      discountPercentage: discountPercentage,
      discountValue: discountValue,
      productCount: productCount,
      startDate: startDate ?? DateTime(2026, 1, 12),
      endDate: endDate ?? DateTime(2026, 1, 20),
    );

class FakeOffersRepo implements OffersRepository {
  FakeOffersRepo({this.page, this.listError, this.assignError, this.assignResult});

  /// Page returned by [fetchOffers] on success.
  final OfferListPage? page;

  /// When set, thrown by [fetchOffers].
  final Object? listError;

  /// When set, thrown by [assignOffer].
  final Object? assignError;

  /// Result returned by [assignOffer] on success.
  final OfferAssignResult? assignResult;

  final List<String?> requestedStatuses = [];
  int fetchCalls = 0;
  int assignCalls = 0;

  @override
  Future<OfferListPage> fetchOffers(
    int shopId,
    String token, {
    String? status,
  }) async {
    fetchCalls++;
    requestedStatuses.add(status);
    if (listError != null) throw listError!;
    return page ?? const OfferListPage(items: [], count: 0);
  }

  @override
  Future<OfferAssignResult> assignOffer(
    int shopId,
    OfferAssignRequest request,
    String token,
  ) async {
    assignCalls++;
    if (assignError != null) throw assignError!;
    return assignResult ??
        const OfferAssignResult(
          offerId: 1,
          title: 'Monsoon Sale',
          productCount: 1,
        );
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


// ---- Products fakes ---------------------------------------------------------

class FakeProductRepo implements ProductRepository {
  FakeProductRepo({
    this.items = const [],
    this.onCreate,
    this.onUpdate,
    this.onAdjustStock,
    this.onHistory,
  });

  /// Items returned by [fetchInventoryOverview].
  final List<ShopProductItem> items;

  /// Optional hooks overriding the create/update response.
  final ShopProductItem? Function(Map<String, dynamic> payload)? onCreate;
  final ShopProductItem? Function(int productId, Map<String, dynamic> fields)?
      onUpdate;

  int overviewCalls = 0;
  int? lastShopId;
  Map<String, dynamic>? lastCreatePayload;
  int? lastUpdatedId;
  Map<String, dynamic>? lastUpdateFields;

  ShopProductItem _itemFromPayload(Map<String, dynamic> payload) =>
      ShopProductItem(
        id: 77,
        name: payload['name'] as String? ?? 'New product',
        status: 'ACTIVE',
        price: (payload['price'] as num?)?.toDouble() ?? 0,
        isActive: true,
        isAvailable: payload['is_available'] as bool? ?? true,
        quantity: payload['quantity'] as int? ?? 0,
        stockStatus: 'IN_STOCK',
      );

  @override
  Future<InventoryOverview> fetchInventoryOverview(
    int shopId,
    String token,
  ) async {
    overviewCalls++;
    lastShopId = shopId;
    final summary = (
      total: items.length,
      active: items.where((i) => i.isActive && i.isAvailable).length,
      inStock: items.where((i) => i.stockStatus == 'IN_STOCK').length,
      lowStock: items.where((i) => i.isLowStock).length,
      outOfStock: items.where((i) => i.isOutOfStock).length,
      totalUnits: items.fold(0, (sum, i) => sum + i.quantity),
    );
    return InventoryOverview(items: items, summary: summary);
  }

  @override
  Future<ShopProductItem> createProduct(
    int shopId,
    Map<String, dynamic> payload,
    String token,
  ) async {
    lastShopId = shopId;
    lastCreatePayload = payload;
    final overridden = onCreate?.call(payload);
    if (overridden != null) return overridden;
    return _itemFromPayload(payload);
  }

  @override
  Future<ShopProductItem> updateProduct(
    int shopId,
    int productId,
    Map<String, dynamic> fields,
    String token,
  ) async {
    lastShopId = shopId;
    lastUpdatedId = productId;
    lastUpdateFields = fields;
    final overridden = onUpdate?.call(productId, fields);
    if (overridden != null) return overridden;
    return _itemFromPayload(fields);
  }

  /// Overrides the [adjustStock] response; receives
  /// `(shopId, productId, payload, token)`. Return a [StockAdjustmentResult]
  /// to succeed, or throw to simulate a rejection.
  final StockAdjustmentResult? Function(
          int, int, Map<String, dynamic>, String)?
      onAdjustStock;

  /// Overrides the [fetchProductHistory] response.
  final ProductHistoryResult? Function(int, int, String)? onHistory;

  int adjustStockCalls = 0;
  int historyCalls = 0;
  int? lastAdjustedId;
  Map<String, dynamic>? lastAdjustPayload;
  int? lastHistoryProductId;

  @override
  Future<StockAdjustmentResult> adjustStock(
    int shopId,
    int productId,
    Map<String, dynamic> payload,
    String token,
  ) async {
    adjustStockCalls++;
    lastShopId = shopId;
    lastAdjustedId = productId;
    lastAdjustPayload = payload;
    final overridden = onAdjustStock?.call(shopId, productId, payload, token);
    if (overridden != null) return overridden;
    final delta = (payload['quantity_adjustment'] as num?)?.toInt() ?? 0;
    final base = items.where((i) => i.id == productId).firstOrNull;
    final previous = base?.quantity ?? 0;
    return StockAdjustmentResult(
      shopProductId: productId,
      previousQuantity: previous,
      quantityAdjustment: delta,
      newQuantity: previous + delta,
      stockStatus: 'IN_STOCK',
      adjustmentType: payload['adjustment_type'] as String?,
    );
  }

  @override
  Future<ProductHistoryResult> fetchProductHistory(
    int shopId,
    int productId,
    String token,
  ) async {
    historyCalls++;
    lastShopId = shopId;
    lastHistoryProductId = productId;
    final overridden = onHistory?.call(shopId, productId, token);
    if (overridden != null) return overridden;
    return ProductHistoryResult(shopProductId: productId, entries: const []);
  }
}

// ---- Reports / Insights fakes ----------------------------------------------

/// Mirrors the `GET /shopkeeper/shops/{id}/analytics/full` payload
/// (`backend/app/services/shopkeeper_analytics.py`). Pass [empty] to model a
/// shop with no recorded customer activity yet.
Map<String, dynamic> insightsJson({bool empty = false}) => {
  'overview': {
    'views': {
      'today': empty ? 0 : 42,
      'yesterday': empty ? 0 : 30,
      'change_pct': empty ? 0 : 40.0,
      'this_week': empty ? 0 : 210,
      'last_week': empty ? 0 : 180,
      'week_change_pct': empty ? 0 : 16.7,
    },
    'clicks': {
      'today': empty ? 0 : 12,
      'this_week': empty ? 0 : 80,
    },
    'interactions': {
      'today': empty ? 0 : 5,
      'this_week': empty ? 0 : 33,
    },
    'generated_at': '2026-01-31T10:00:00',
  },
  'views_timeseries': empty
      ? const []
      : const [
          {'date': '2026-01-30', 'views': 30},
          {'date': '2026-01-31', 'views': 42},
        ],
  'clicks_timeseries': empty
      ? const []
      : const [
          {'date': '2026-01-30', 'clicks': 9},
          {'date': '2026-01-31', 'clicks': 12},
        ],
  'top_products': empty
      ? const []
      : const [
          {'shop_product_id': 7, 'sku': 'SKU-RICE-1', 'views': 25},
          {'shop_product_id': 8, 'sku': '', 'views': 11},
        ],
  'top_searches': empty
      ? const []
      : const [
          {'query': 'basmati rice', 'count': 9},
        ],
  'interactions': {
    'call_views': empty ? 0 : 3,
    'messages': empty ? 0 : 2,
    'ratings': empty ? 0 : 1,
    'period_days': 30,
  },
  'devices': empty
      ? const <String, dynamic>{}
      : const {'android': 30, 'ios': 10, 'unknown': 2},
  'hourly': empty
      ? const []
      : const [
          {'hour': 0, 'views': 0},
          {'hour': 9, 'views': 4},
          {'hour': 18, 'views': 12},
        ],
  'freshness': {
    'score': empty ? 0 : 75.0,
    'total_products': empty ? 0 : 20,
    'fresh': empty ? 0 : 15,
    'stale': empty ? 0 : 5,
  },
};

class FakeInsightsRepo implements InsightsRepository {
  FakeInsightsRepo({this.json, this.error});

  /// Raw payload returned on success (defaults to [insightsJson]).
  final Map<String, dynamic>? json;

  /// When set, thrown instead of returning [json].
  final Object? error;

  int calls = 0;
  int? lastShopId;
  int? lastDays;

  @override
  Future<InsightsBundle> fetchInsights(
    int shopId,
    String token, {
    int days = kInsightsDefaultRange,
  }) async {
    calls++;
    lastShopId = shopId;
    lastDays = days;
    if (error != null) throw error!;
    return InsightsBundle.fromJson(json ?? insightsJson());
  }
}

// ---- POS fakes --------------------------------------------------------------

/// One POS integration fixture. Defaults describe a CONNECTED integration.
PosIntegration posIntegration({
  int id = 50,
  int shopId = 10,
  String providerCode = 'MOCK',
  String providerName = 'Mock POS (built-in)',
  String status = 'ACTIVE',
  int mappedProducts = 12,
  int deviceCount = 1,
  DateTime? lastSyncAt,
  String? lastSyncStatus,
  PosSyncJob? latestJob,
}) =>
    PosIntegration(
      id: id,
      shopId: shopId,
      providerCode: providerCode,
      providerName: providerName,
      status: status,
      syncEnabled: status == 'ACTIVE',
      syncIntervalMinutes: 30,
      mappedProducts: mappedProducts,
      deviceCount: deviceCount,
      lastSyncAt: lastSyncAt,
      lastSyncStatus: lastSyncStatus,
      latestJob: latestJob,
    );

/// One sync-job fixture. Defaults describe a completed successful full sync.
PosSyncJob posJob({
  int id = 900,
  String syncType = 'FULL',
  String status = 'COMPLETED',
  String trigger = 'MANUAL',
  int itemsProcessed = 5,
  int itemsSucceeded = 5,
  int itemsFailed = 0,
  String? errorSummary,
  DateTime? startedAt,
  DateTime? completedAt,
}) =>
    PosSyncJob(
      id: id,
      syncType: syncType,
      status: status,
      trigger: trigger,
      itemsProcessed: itemsProcessed,
      itemsSucceeded: itemsSucceeded,
      itemsFailed: itemsFailed,
      errorSummary: errorSummary,
      startedAt: startedAt ?? DateTime(2026, 9, 14, 9, 30),
      completedAt: completedAt ?? DateTime(2026, 9, 14, 9, 31),
    );

/// In-memory POS backend: [register] appends a PENDING integration, [connect]
/// flips it per [connectResult] so the controller's reload sees the new state.
class FakePosRepo implements PosRepository {
  FakePosRepo({
    List<PosIntegration>? integrations,
    this.providers = const [
      PosProviderInfo(
        code: 'MOCK',
        displayName: 'Mock POS (built-in)',
        supportsIncremental: true,
      ),
    ],
    this.jobs = const [],
    this.statusResult,
    this.connectResult = true,
    this.listError,
    this.connectError,
    this.syncError,
    this.syncJobResult,
  }) : integrations = integrations ?? [];

  final List<PosIntegration> integrations;
  final List<PosProviderInfo> providers;
  final List<PosSyncJob> jobs;

  /// Overrides `.../status` responses (defaults to the stored integration).
  final PosIntegration? statusResult;

  /// What `connect` reports (false simulates a credential refusal).
  final bool connectResult;

  /// When set, listIntegrations throws this.
  final Object? listError;

  /// When set, connect throws this.
  final Object? connectError;

  /// When set, triggerSync throws this.
  final Object? syncError;

  /// Returned by triggerSync on success.
  final PosSyncJob? syncJobResult;

  int providerCalls = 0;
  int listCalls = 0;
  int registerCalls = 0;
  int connectCalls = 0;
  int disconnectCalls = 0;
  int syncCalls = 0;
  int statusCalls = 0;
  int jobsCalls = 0;

  String? lastRegisteredProvider;

  @override
  Future<List<PosProviderInfo>> listProviders(String token) async {
    providerCalls++;
    return providers;
  }

  @override
  Future<List<PosIntegration>> listIntegrations(
    int shopId,
    String token,
  ) async {
    listCalls++;
    if (listError != null) throw listError!;
    return integrations
        .where((i) => i.shopId == shopId)
        .toList(growable: false);
  }

  @override
  Future<PosIntegration> register(
    int shopId,
    String providerCode,
    String token, {
    String integrationType = 'API',
  }) async {
    registerCalls++;
    lastRegisteredProvider = providerCode;
    final created = posIntegration(
      id: 77,
      shopId: shopId,
      providerCode: providerCode,
      status: 'PENDING',
    );
    integrations.add(created);
    return created;
  }

  @override
  Future<bool> connect(int integrationId, String token) async {
    connectCalls++;
    if (connectError != null) throw connectError!;
    if (connectResult) {
      final i = integrations.indexWhere((x) => x.id == integrationId);
      if (i != -1) integrations[i] = posIntegration(id: integrationId, status: 'ACTIVE');
    }
    return connectResult;
  }

  @override
  Future<PosIntegration> disconnect(int integrationId, String token) async {
    disconnectCalls++;
    final i = integrations.indexWhere((x) => x.id == integrationId);
    if (i != -1) {
      integrations[i] = posIntegration(id: integrationId, status: 'DISCONNECTED');
      return integrations[i];
    }
    return posIntegration(id: integrationId, status: 'DISCONNECTED');
  }

  @override
  Future<PosSyncJob> triggerSync(
    int integrationId,
    String token, {
    String syncType = 'FULL',
  }) async {
    syncCalls++;
    if (syncError != null) throw syncError!;
    return syncJobResult ?? posJob();
  }

  @override
  Future<PosIntegration> status(int integrationId, String token) async {
    statusCalls++;
    return statusResult ??
        integrations.firstWhere((x) => x.id == integrationId, orElse: () => posIntegration(id: integrationId));
  }

  @override
  Future<List<PosSyncJob>> listJobs(
    int integrationId,
    String token, {
    int limit = 20,
  }) async {
    jobsCalls++;
    return jobs;
  }
}
