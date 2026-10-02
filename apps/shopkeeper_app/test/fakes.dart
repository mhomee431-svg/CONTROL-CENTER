import 'dart:async';
import 'dart:typed_data';

import 'package:hyperlocal_shopkeeper_app/core/auth/firebase_auth_service.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/account/data/sessions_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/account/domain/device_session.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/data/auth_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/domain/auth_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/barcode/data/barcode_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/barcode/domain/barcode_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/dashboard/data/dashboard_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/data/inventory_repository.dart';
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
import 'package:hyperlocal_shopkeeper_app/features/products/data/category_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/data/product_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/category_taxonomy.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/data/holiday_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/domain/holiday_models.dart';
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

/// A CONFIRMED non-shopkeeper account (e.g. a customer sign-in on the
/// shopkeeper app) — the router's SHOPKEEPER gate must dead-end this at the
/// account-status screen. Carries a shop on purpose: if the gate ever stops
/// working, the test would otherwise fail for the wrong reason (profile).
AuthSession makeNonShopkeeperSession() => AuthSession(
  user: const ShopkeeperUser(
    id: 4,
    phoneNumber: '+919000000004',
    name: 'Customer Account',
    status: 'ACTIVE',
    role: 'customer',
    isShopkeeper: false,
  ),
  shops: [ownerShop(id: 77, name: 'Someone Elses Shop')],
);

/// Shopkeeper whose user payload EXPLICITLY confirms shopkeeper access
/// (`is_shopkeeper: true` — as `GET /auth/me` returns).
AuthSession makeConfirmedShopkeeperSession() => AuthSession(
  user: const ShopkeeperUser(
    id: 5,
    phoneNumber: '+919000000005',
    name: 'Confirmed Shopkeeper',
    status: 'ACTIVE',
    role: 'shopkeeper',
    isShopkeeper: true,
  ),
  shops: [ownerShop()],
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
  Future<AuthSession> createProfile({required String name}) async {
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
  FakeShopRepo({List<ShopSummary>? shops, this.detail})
      : shops = shops ?? [ownerShop()];

  final List<ShopSummary> shops;

  /// Returned by [getShopDetail]; defaults to [shopDetailFixture].
  ShopDetail? detail;
  int registeredShops = 0;
  String? lastRegisteredName;

  /// Profile / settings field maps sent through the update endpoints.
  final List<Map<String, dynamic>> profileCalls = [];
  final List<Map<String, dynamic>> settingsCalls = [];

  /// The last weekly schedule sent through [saveOperatingHours].
  List<ShopHourEntry>? lastSavedHours;
  int hoursReads = 0;
  List<ShopHourEntry> storedHours = ShopHourEntry.defaultWeek();

  @override
  Future<List<ShopSummary>> listMyShops(String token) async => shops;

  @override
  Future<ShopDetail> getShopDetail(int shopId, String token) async =>
      detail ?? shopDetailFixture();

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
  Future<void> updateShopProfile(
    int shopId,
    Map<String, dynamic> fields,
    String token,
  ) async {
    profileCalls.add(fields);
  }

  @override
  Future<void> updateSettings(
    int shopId,
    Map<String, dynamic> fields,
    String token,
  ) async {
    settingsCalls.add(fields);
  }

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
  }) =>
      saveOperatingHours(
        shopId: shopId,
        token: token,
        hours: [
          for (var day = 0; day < 7; day++)
            ShopHourEntry(
              dayOfWeek: day,
              openTime: openTime,
              closeTime: closeTime,
              isClosed: false,
            ),
        ],
      );

  @override
  Future<List<ShopHourEntry>> fetchOperatingHours(
    int shopId,
    String token,
  ) async {
    hoursReads++;
    return storedHours;
  }

  @override
  Future<void> saveOperatingHours({
    required int shopId,
    required List<ShopHourEntry> hours,
    required String token,
  }) async {
    lastSavedHours = hours;
    storedHours = hours;
  }
}

/// A full, realistic shop payload for the Shop Profile screens — mirrors the
/// real `GET /shopkeeper/shops/{id}` contract (identity, contacts, toggles,
/// location, verification timeline, subscription, rating).
ShopDetail shopDetailFixture({
  int id = 10,
  String name = 'Sharma Kirana Store',
  String? category = 'GROCERY',
  bool verified = true,
  bool acceptingOrders = true,
  bool open24x7 = false,
  double? latitude = 24.814512,
  double? longitude = 84.234501,
}) => ShopDetail(
      summary: ShopSummary(
        id: id,
        name: name,
        status: verified ? 'ACTIVE' : 'REGISTERED',
        isVerified: verified,
        category: category,
        membership: 'owner',
        permissions: const ['update:shop', 'create:product'],
      ),
      tagline: 'Fresh stock, fair prices',
      description: 'Everyday essentials from your neighbourhood store.',
      phone: '+91 98765 43210',
      alternatePhone: '+91 98765 43211',
      whatsappNumber: '+91 98765 43210',
      email: 'shop@example.com',
      websiteUrl: 'https://sharmakirana.example.com',
      gstin: '22AAAAA0000A1Z5',
      createdAt: '2026-01-12T09:30:00Z',
      latitude: latitude,
      longitude: longitude,
      verification: const VerificationInfo(
        status: 'VERIFIED',
        submittedAt: '2026-01-12T10:00:00Z',
        reviewedAt: '2026-01-13T12:00:00Z',
        verifiedAt: '2026-01-13T12:00:00Z',
      ),
      subscription: const SubscriptionInfo(status: 'ACTIVE', plan: 'GROWTH'),
      rating: 4.2,
      reviewCount: 18,
      isAcceptingOrders: acceptingOrders,
      isDeliveryAvailable: true,
      isPickupAvailable: false,
      isOpen24x7: open24x7,
      minOrderAmount: 199,
      deliveryRadiusKm: 6,
      deliveryFee: 25,
      freeDeliveryAbove: 499,
    );

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
      payload: n.payload,
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
/// One notification row for list/strip fixtures.
///
/// [createdAt] is fixed by default so relative time labels stay stable
/// regardless of when the suite runs.
ShopkeeperNotification notificationFixture({
  int id = 1,
  String title = 'Low stock: Amul Milk',
  String body = 'Only 3 left in store',
  String type = 'INVENTORY_LOW',
  bool isRead = false,
  DateTime? createdAt,
}) =>
    ShopkeeperNotification(
      id: id,
      title: title,
      body: body,
      type: type,
      isRead: isRead,
      createdAt: createdAt ?? DateTime(2026, 9, 10, 8),
    );

class FakeNotificationsRepo implements NotificationsRepository {
  FakeNotificationsRepo({
    this.page,
    this.error,
    this.markAsReadError,
    this.allItems,
  });

  /// Notifications page returned on success (the baseline state).
  final NotificationsPage? page;

  /// When set, thrown by [fetchNotifications].
  final Object? error;

  /// When set, markAsRead throws this error.
  final Object? markAsReadError;

  final List<int> markedRead = [];
  int fetchCalls = 0;

  /// The `offset` of every fetch, in order — the proof that "Load more" asks
  /// for the rows it does not already hold.
  final List<int> requestedOffsets = [];

  /// Full fixture for PAGED reads.
  ///
  /// When set, the fake slices it by `limit`/`offset` exactly like the shop
  /// notifications endpoint and reports the server's total, so a "Load more"
  /// test pages through real second-page rows instead of replaying page one.
  final List<ShopkeeperNotification>? allItems;

  /// Bulk mark-all-read calls (the controller must use ONE call, not a loop).
  int markAllAsReadCalls = 0;

  @override
  Future<NotificationsPage> fetchNotifications(
    int shopId,
    String token, {
    int limit = notificationsPageSize,
    int offset = 0,
  }) async {
    fetchCalls++;
    requestedOffsets.add(offset);
    if (error != null) throw error!;
    final full = allItems;
    if (full != null) {
      final start = offset < full.length ? offset : full.length;
      final end = offset + limit < full.length ? offset + limit : full.length;
      return NotificationsPage(
        items: full.sublist(start, end),
        // The backend counts unread across the WHOLE shop-scoped set, not just
        // the returned page — the fake does the same.
        unreadCount: full.where((n) => n.isUnread).length,
        total: full.length,
      );
    }
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
      total: base.total == 0 ? items.length : base.total,
    );
  }

  @override
  Future<void> markAsRead(int notificationId, String token) async {
    if (markAsReadError != null) throw markAsReadError!;
    if (!markedRead.contains(notificationId)) markedRead.add(notificationId);
  }

  @override
  Future<void> markAllAsRead(String token) async {
    if (markAsReadError != null) throw markAsReadError!;
    for (final n in (page?.items ?? const <ShopkeeperNotification>[])) {
      if (!markedRead.contains(n.id)) markedRead.add(n.id);
    }
    markAllAsReadCalls++;
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
  double? promotionalPrice,
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
      promotionalPrice: promotionalPrice,
      productCount: productCount,
      startDate: startDate ?? DateTime(2026, 1, 12),
      endDate: endDate ?? DateTime(2026, 1, 20),
    );

class FakeOffersRepo implements OffersRepository {
  FakeOffersRepo({
    this.page,
    this.listError,
    this.assignError,
    this.assignResult,
    this.statusError,
    this.statusResult,
  });

  /// Page returned by [fetchOffers] on success.
  final OfferListPage? page;

  /// When set, thrown by [fetchOffers].
  final Object? listError;

  /// When set, thrown by [assignOffer].
  final Object? assignError;

  /// Result returned by [assignOffer] on success.
  final OfferAssignResult? assignResult;

  /// When set, thrown by [updateOfferStatus].
  final Object? statusError;

  /// Result returned by [updateOfferStatus] on success.
  final OfferSummary? statusResult;

  final List<String?> requestedStatuses = [];

  /// Statuses passed to [updateOfferStatus], in call order.
  final List<String> requestedTransitions = [];
  int fetchCalls = 0;
  int assignCalls = 0;
  int statusCalls = 0;

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

  @override
  Future<OfferSummary> updateOfferStatus(
    int shopId,
    int offerId,
    String status,
    String token,
  ) async {
    statusCalls++;
    requestedTransitions.add(status);
    if (statusError != null) throw statusError!;
    return statusResult ??
        offerSummary(id: offerId, status: status, displayStatus: status);
  }
}

// ---- Inventory import fakes ------------------------------------------------

class FakeImportRepo implements InventoryImportRepository {
  FakeImportRepo({
    this.onUpload,
    this.onConfirm,
    this.onList,
    this.allJobs,
    this.error,
    this.sampleBytes,
  });

  /// When set, returned from upload/preview list calls.
  final ImportPreview? onUpload;
  final ImportConfirmResult? onConfirm;
  final List<ImportJob>? onList;

  /// Full fixture for PAGED reads.
  ///
  /// When set, the fake slices it by `limit`/`offset` exactly like the backend
  /// and reports the server's total — so a "Load more" test sees real second-page
  /// rows instead of a replay of page one.
  final List<ImportJob>? allJobs;

  /// When set, thrown from every call (simulates a network failure).
  final Object? error;

  /// Returned by [downloadSample] (defaults to a plausible .xlsx magic).
  final Uint8List? sampleBytes;

  /// The `offset` of every list request, in order — the proof that paging asks
  /// for the rows it does not already hold.
  final List<int> requestedJobOffsets = [];

  int uploadCalls = 0;
  int confirmCalls = 0;
  int sampleCalls = 0;
  int? lastShopId;
  int? lastSampleShopId;
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
  Future<ImportJobPage> listJobs(
    int shopId,
    String token, {
    int limit = importJobsPageSize,
    int offset = 0,
  }) async {
    lastShopId = shopId;
    requestedJobOffsets.add(offset);
    if (error != null) throw error!;
    final full = allJobs;
    if (full != null) {
      final start = offset < full.length ? offset : full.length;
      final end = offset + limit < full.length ? offset + limit : full.length;
      return ImportJobPage(jobs: full.sublist(start, end), total: full.length);
    }
    final jobs = onList ??
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
    return ImportJobPage(jobs: jobs, total: jobs.length);
  }

  @override
  Future<Uint8List> downloadSample(int shopId, String token) async {
    sampleCalls++;
    lastSampleShopId = shopId;
    if (error != null) throw error!;
    return sampleBytes ?? Uint8List.fromList(const [0x50, 0x4b, 0x03, 0x04]);
  }
}


// ---- Products fakes ---------------------------------------------------------

/// Fake for BOTH the product-CRUD and the inventory repository seams — the
/// shop-catalog fixtures (items, stock knobs) are shared by the products and
/// the inventory flows, so one fake keeps the two provider overrides in sync.
class FakeProductRepo implements ProductRepository, InventoryRepository {
  FakeProductRepo({
    this.items = const [],
    this.onCreate,
    this.onUpdate,
    this.onAdjustStock,
    this.onHistory,
    this.allHistoryEntries,
    this.onLowStockThreshold,
    this.onAdjustments,
    this.serverOnly = const [],
    this.onSearch,
  });

  /// Items returned by [fetchInventoryOverview]. Mutable on purpose: a test
  /// that models "the server's payload changed" REPLACES the list (the lists
  /// in the app are immutable and identity-cached, so in-place edits would be
  /// invisible).
  List<ShopProductItem> items;

  /// Rows ONLY the server knows — the stale-catalog fixture behind the
  /// products screen's server-search path (a listing added after the last
  /// load / on another device). The default search matches over
  /// `items + serverOnly`, exactly like the backend searches its own table.
  final List<ShopProductItem> serverOnly;

  /// Optional override for [searchInventoryList]: returns the server's answer
  /// (or throws to model a failed round-trip). When null the fake mirrors the
  /// backend rule — name / sku contains, case-insensitive — over
  /// `items + serverOnly`.
  final Future<List<ShopProductItem>> Function(String query)? onSearch;

  /// Optional hooks overriding the create/update response.
  final ShopProductItem? Function(Map<String, dynamic> payload)? onCreate;
  final ShopProductItem? Function(int productId, Map<String, dynamic> fields)?
      onUpdate;

  int overviewCalls = 0;

  /// How often the COUNTS-ONLY view was asked for. The dashboard uses
  /// `fetchInventorySummary` precisely so it never has to download the
  /// catalogue, so a test can assert `summaryCalls == 1 && overviewCalls == 0`
  /// to prove the home screen took the small payload.
  int summaryCalls = 0;

  /// When set, [fetchInventoryOverview] waits for it before answering — lets a
  /// test observe the IN-FLIGHT window of a (silent) refresh.
  Completer<void>? overviewGate;

  /// When true, [fetchInventoryOverview] throws — the failed-refresh fixture.
  bool failOverview = false;

  int? lastShopId;
  Map<String, dynamic>? lastCreatePayload;
  int? lastUpdatedId;
  Map<String, dynamic>? lastUpdateFields;

  /// Server-search observability: how often the screen reached the backend,
  /// and with which term — asserted by the server-search tests.
  int searchCalls = 0;
  String? lastSearchQuery;

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

  /// The counts the backend derives from the same rows — shared by both reads
  /// so the full-list and the counts-only answers can never disagree.
  InventorySummary get _derivedSummary => (
        total: items.length,
        active: items.where((i) => i.isActive && i.isAvailable).length,
        inStock: items.where((i) => i.stockStatus == 'IN_STOCK').length,
        lowStock: items.where((i) => i.isLowStock).length,
        outOfStock: items.where((i) => i.isOutOfStock).length,
        totalUnits: items.fold(0, (sum, i) => sum + i.quantity),
        stale: items.where((i) => i.isStale).length,
      );

  @override
  Future<InventoryOverview> fetchInventoryOverview(
    int shopId,
    String token,
  ) async {
    overviewCalls++;
    lastShopId = shopId;
    await overviewGate?.future;
    if (failOverview) throw Exception('offline');
    return InventoryOverview(items: items, summary: _derivedSummary);
  }

  @override
  Future<InventorySummary> fetchInventorySummary(
    int shopId,
    String token,
  ) async {
    summaryCalls++;
    lastShopId = shopId;
    if (failOverview) throw Exception('offline');
    return _derivedSummary;
  }

  @override
  Future<List<ShopProductItem>> searchInventoryList(
      int shopId, String token, String query) async {
    searchCalls++;
    lastSearchQuery = query;
    lastShopId = shopId;
    final hooked = onSearch;
    if (hooked != null) return hooked(query);
    // Mirror the backend: normalized substring over name / sku.
    final needle = query.trim().toLowerCase();
    return [
      for (final item in [...items, ...serverOnly])
        if (item.name.toLowerCase().contains(needle) ||
            (item.sku ?? '').toLowerCase().contains(needle))
          item,
    ];
  }

  int clearSnapshotCalls = 0;

  @override
  Future<void> clearOfflineSnapshot() async {
    clearSnapshotCalls++;
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

  /// Full fixture for PAGED history reads.
  ///
  /// When set, the fake slices it by `limit`/`offset` like the backend and
  /// reports `total` / `has_more`, so a history "Load more" test pages through
  /// real second-page entries instead of replaying the first page.
  final List<ProductHistoryEntry>? allHistoryEntries;

  int adjustStockCalls = 0;
  int historyCalls = 0;
  int? lastAdjustedId;
  Map<String, dynamic>? lastAdjustPayload;
  int? lastHistoryProductId;

  /// The `offset` of every history request, in order.
  final List<int> requestedHistoryOffsets = [];

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
    String token, {
    int limit = productHistoryPageSize,
    int offset = 0,
  }) async {
    historyCalls++;
    lastShopId = shopId;
    lastHistoryProductId = productId;
    requestedHistoryOffsets.add(offset);
    final full = allHistoryEntries;
    if (full != null) {
      final start = offset < full.length ? offset : full.length;
      final end = offset + limit < full.length ? offset + limit : full.length;
      return ProductHistoryResult(
        shopProductId: productId,
        entries: full.sublist(start, end),
        total: full.length,
        offset: offset,
        limit: limit,
        hasMore: end < full.length,
        currentQuantity: 12,
        stockStatus: 'IN_STOCK',
      );
    }
    final overridden = onHistory?.call(shopId, productId, token);
    if (overridden != null) return overridden;
    return ProductHistoryResult(shopProductId: productId, entries: const []);
  }

  /// Overrides the [updateLowStockThreshold] response.
  final LowStockThresholdResult? Function(int, int, int, String)?
      onLowStockThreshold;

  /// Overrides the [fetchStockAdjustments] response.
  final StockAdjustmentHistory? Function(int, int, String)? onAdjustments;

  int thresholdCalls = 0;
  int adjustmentsCalls = 0;
  int? lastThresholdId;
  int? lastThresholdValue;
  int? lastAdjustmentsProductId;

  @override
  Future<LowStockThresholdResult> updateLowStockThreshold(
    int shopId,
    int productId,
    int threshold,
    String token,
  ) async {
    thresholdCalls++;
    lastShopId = shopId;
    lastThresholdId = productId;
    lastThresholdValue = threshold;
    final overridden =
        onLowStockThreshold?.call(shopId, productId, threshold, token);
    if (overridden != null) return overridden;
    final base = items.where((i) => i.id == productId).firstOrNull;
    final quantity = base?.quantity ?? 0;
    // Mirror the server rule: the threshold decides LOW_STOCK, so re-derive
    // the state from the (unchanged) quantity.
    final status = quantity <= 0
        ? 'OUT_OF_STOCK'
        : (quantity <= threshold ? 'LOW_STOCK' : 'IN_STOCK');
    return LowStockThresholdResult(
      shopProductId: productId,
      previousLowStockThreshold: threshold,
      lowStockThreshold: threshold,
      quantity: quantity,
      stockStatus: status,
    );
  }

  @override
  Future<StockAdjustmentHistory> fetchStockAdjustments(
    int shopId,
    int productId,
    String token,
  ) async {
    adjustmentsCalls++;
    lastShopId = shopId;
    lastAdjustmentsProductId = productId;
    final overridden = onAdjustments?.call(shopId, productId, token);
    if (overridden != null) return overridden;
    return StockAdjustmentHistory(
      shopProductId: productId,
      adjustments: const [],
    );
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
  FakeInsightsRepo({
    this.json,
    this.error,
    this.viewsSeries = const <InsightsPoint>[],
    this.clicksSeries = const <InsightsPoint>[],
    this.topProducts = const <TopProduct>[],
    this.hourly = const <HourlyPoint>[],
    this.businessInsights = const BusinessInsightsBundle(),
  });

  /// Raw payload returned on success (defaults to [insightsJson]).
  final Map<String, dynamic>? json;

  /// When set, thrown instead of returning [json] (all endpoints). Mutable
  /// so widget tests can clear a failure mid-test (Retry flows).
  Object? error;

  /// Granular drill-down payloads. Mutable for the same reason.
  List<InsightsPoint> viewsSeries;
  List<InsightsPoint> clicksSeries;
  List<TopProduct> topProducts;
  List<HourlyPoint> hourly;

  /// Live business-insight cards. Defaults to an EMPTY bundle, which hides the
  /// section entirely — tests that don't care about the cards are unaffected.
  BusinessInsightsBundle businessInsights;

  /// When set, [fetchBusinessInsights] throws this instead of returning
  /// [businessInsights] — independent of [error], so a test can fail just the
  /// insight cards and assert the section reports the failure.
  Object? businessInsightsError;

  int calls = 0;
  int viewsCalls = 0;
  int clicksCalls = 0;
  int topProductsCalls = 0;
  int hourlyCalls = 0;
  int businessInsightsCalls = 0;
  int? lastShopId;
  int? lastDays;
  int? lastTopProductsDays;
  int? lastTopProductsLimit;
  int? lastHourlyDays;

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

  @override
  Future<BusinessInsightsBundle> fetchBusinessInsights(
    int shopId,
    String token,
  ) async {
    businessInsightsCalls++;
    lastShopId = shopId;
    if (businessInsightsError != null) throw businessInsightsError!;
    if (error != null) throw error!;
    return businessInsights;
  }

  @override
  Future<List<InsightsPoint>> fetchViewsSeries(
    int shopId,
    String token, {
    int days = kInsightsDefaultRange,
  }) async {
    viewsCalls++;
    lastShopId = shopId;
    lastDays = days;
    if (error != null) throw error!;
    return viewsSeries;
  }

  @override
  Future<List<InsightsPoint>> fetchClicksSeries(
    int shopId,
    String token, {
    int days = kInsightsDefaultRange,
  }) async {
    clicksCalls++;
    lastShopId = shopId;
    lastDays = days;
    if (error != null) throw error!;
    return clicksSeries;
  }

  @override
  Future<List<TopProduct>> fetchTopProducts(
    int shopId,
    String token, {
    int days = kInsightsDefaultRange,
    int limit = kInsightsMaxTopProducts,
  }) async {
    topProductsCalls++;
    lastShopId = shopId;
    lastTopProductsDays = days;
    lastTopProductsLimit = limit;
    if (error != null) throw error!;
    return topProducts;
  }

  @override
  Future<List<HourlyPoint>> fetchHourly(
    int shopId,
    String token, {
    int days = kInsightsDefaultRange,
  }) async {
    hourlyCalls++;
    lastShopId = shopId;
    lastHourlyDays = days;
    if (error != null) throw error!;
    return hourly;
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
    this.providersError,
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

  /// When set, listProviders throws this.
  final Object? providersError;

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
  int reconnectCalls = 0;
  int credentialsCalls = 0;
  int disconnectCalls = 0;

  /// Last credential rotation received (null fields = left untouched).
  ({String? apiKey, String? apiSecret, String? apiBaseUrl})? lastCredentials;
  int syncCalls = 0;
  int statusCalls = 0;
  int jobsCalls = 0;

  String? lastRegisteredProvider;

  @override
  Future<List<PosProviderInfo>> listProviders(String token) async {
    providerCalls++;
    if (providersError != null) throw providersError!;
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
  Future<bool> reconnect(int integrationId, String token) async {
    reconnectCalls++;
    if (connectError != null) throw connectError!;
    if (connectResult) {
      final i = integrations.indexWhere((x) => x.id == integrationId);
      if (i != -1) {
        integrations[i] = posIntegration(id: integrationId, status: 'ACTIVE');
      }
    }
    return connectResult;
  }

  @override
  Future<PosIntegration> updateCredentials(
    int integrationId,
    String token, {
    String? apiKey,
    String? apiSecret,
    String? apiBaseUrl,
  }) async {
    credentialsCalls++;
    lastCredentials = (
      apiKey: apiKey,
      apiSecret: apiSecret,
      apiBaseUrl: apiBaseUrl,
    );
    final i = integrations.indexWhere((x) => x.id == integrationId);
    return i != -1 ? integrations[i] : posIntegration(id: integrationId);
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

  // ── Terminals / schedule / settings / diagnostics ────────────────────────
  int getIntegrationCalls = 0;
  int scheduleCalls = 0;
  int configCalls = 0;
  int listDevicesCalls = 0;
  int registerDeviceCalls = 0;
  int jobDetailCalls = 0;
  int retryCalls = 0;

  /// Terminals the fake reports; mutated by [registerDevice].
  final List<PosDevice> devices = <PosDevice>[];
  PosJobDetail? jobDetailResult;
  PosSyncJob? retryResult;
  PosSyncSettings? lastSyncSettings;
  ({int? syncIntervalMinutes, bool? syncEnabled})? lastSchedule;
  Object? devicesError;
  Object? retryError;

  PosIntegration _fresh(int integrationId) => PosIntegration(
        id: integrationId,
        shopId: 10,
        providerCode: 'MOCK',
        providerName: 'Mock POS (built-in)',
        status: 'ACTIVE',
        syncEnabled: true,
        syncIntervalMinutes: 60,
        mappedProducts: 0,
        deviceCount: devices.length,
      );

  @override
  Future<PosIntegration> getIntegration(int integrationId, String token) async {
    getIntegrationCalls++;
    return statusResult ?? _fresh(integrationId);
  }

  @override
  Future<PosIntegration> updateSchedule(
    int integrationId,
    String token, {
    int? syncIntervalMinutes,
    bool? syncEnabled,
  }) async {
    scheduleCalls++;
    lastSchedule =
        (syncIntervalMinutes: syncIntervalMinutes, syncEnabled: syncEnabled);
    return _fresh(integrationId);
  }

  @override
  Future<PosIntegration> updateSyncConfig(
    int integrationId,
    String token,
    PosSyncSettings settings,
  ) async {
    configCalls++;
    lastSyncSettings = settings;
    return _fresh(integrationId);
  }

  @override
  Future<List<PosDevice>> listDevices(int integrationId, String token) async {
    listDevicesCalls++;
    if (devicesError != null) throw devicesError!;
    return List.unmodifiable(devices);
  }

  @override
  Future<PosDevice> registerDevice(
    int integrationId,
    String token, {
    required String deviceIdentifier,
    String? deviceName,
    String? deviceType,
  }) async {
    registerDeviceCalls++;
    if (devicesError != null) throw devicesError!;
    final device = PosDevice(
      id: 500 + devices.length,
      deviceIdentifier: deviceIdentifier,
      deviceName: deviceName,
      deviceType: deviceType,
      isActive: true,
    );
    devices.add(device);
    return device;
  }

  @override
  Future<PosJobDetail> jobDetail(int jobId, String token) async {
    jobDetailCalls++;
    return jobDetailResult ??
        PosJobDetail(
          job: posJob(id: jobId, status: 'FAILED', errorSummary: 'provider 500'),
          logs: const [
            PosJobLog(level: 'ERROR', message: 'Provider unreachable'),
            PosJobLog(level: 'WARNING', message: '3 records skipped'),
          ],
          conflicts: const [
            PosJobConflict(
              posProductCode: 'POS-9',
              field: 'price',
              detail: 'Platform price kept',
              platformValue: '120.00',
              posValue: '99.00',
            ),
          ],
        );
  }

  @override
  Future<PosSyncJob> retryJob(int jobId, String token) async {
    retryCalls++;
    if (retryError != null) throw retryError!;
    return retryResult ?? posJob(id: jobId, status: 'COMPLETED');
  }
}

// ---- Holidays -------------------------------------------------------------

ShopHoliday holidayFixture({
  int id = 1,
  DateTime? date,
  String? reason = 'Diwali',
  bool recurring = false,
}) =>
    ShopHoliday(
      id: id,
      date: date ?? DateTime(2027, 3, 4),
      reason: reason,
      isRecurringYearly: recurring,
    );

/// In-memory [HolidayRepository] recording every call for assertions.
class FakeHolidayRepository implements HolidayRepository {
  FakeHolidayRepository({
    List<ShopHoliday>? holidays,
    this.listError,
    this.addError,
    this.removeError,
  }) : holidays = List<ShopHoliday>.from(holidays ?? const <ShopHoliday>[]);

  final List<ShopHoliday> holidays;

  /// Mutable so widget tests can flip a failure off mid-test (Retry flows).
  Object? listError;
  Object? addError;
  Object? removeError;

  int listCalls = 0;
  int addCalls = 0;
  int removeCalls = 0;
  final List<HolidayDraft> addedDrafts = [];
  final List<int> removedIds = [];
  int _nextId = 1000;

  @override
  Future<List<ShopHoliday>> list(int shopId, String token) async {
    listCalls++;
    if (listError != null) throw listError!;
    final sorted = [...holidays]..sort((a, b) => a.date.compareTo(b.date));
    return List.unmodifiable(sorted);
  }

  @override
  Future<void> add(int shopId, HolidayDraft draft, String token) async {
    addCalls++;
    if (addError != null) throw addError!;
    addedDrafts.add(draft);
    holidays.add(ShopHoliday(
      id: _nextId++,
      date: draft.date,
      reason: draft.reason,
      isRecurringYearly: draft.recurringYearly,
    ));
  }

  @override
  Future<void> remove(int shopId, int holidayId, String token) async {
    removeCalls++;
    if (removeError != null) throw removeError!;
    removedIds.add(holidayId);
    holidays.removeWhere((h) => h.id == holidayId);
  }
}

/// Product taxonomy (`GET /api/v1/categories`).
///
/// Any test that opens the manual product-create sheet MUST override the
/// category repository with this — the sheet resolves the taxonomy on open,
/// and without an override it would attempt a real network call.
class FakeCategoryRepo implements CategoryRepository {
  FakeCategoryRepo({List<CategoryOption>? rows, this.error})
      : rows = rows ??
            const [
              CategoryOption(id: 1, name: 'Grocery', sortOrder: 1),
              CategoryOption(id: 11, name: 'Rice', parentId: 1, sortOrder: 2),
              CategoryOption(id: 2, name: 'Pharmacy', sortOrder: 3),
            ];

  final List<CategoryOption> rows;
  Object? error;
  int calls = 0;

  @override
  Future<CategoryTaxonomy> fetchTaxonomy(String token) async {
    calls++;
    if (error != null) throw error!;
    return CategoryTaxonomy(rows);
  }
}

// ---- Sessions & devices --------------------------------------------------

/// One device-session fixture.
///
/// [withMetadata] off models an older backend row that captured nothing but the
/// session id — the screen must still render it.
DeviceSession deviceSession({
  String sessionId = 'sess-1',
  String? deviceName = 'Ramesh Pixel',
  String? deviceType = 'mobile',
  String? platform = 'Android 14',
  String? appVersion = '1.0.0',
  String? ipAddress = '10.0.0.5',
  DateTime? lastActivityAt,
  DateTime? createdAt,
  bool withMetadata = true,
}) => DeviceSession(
  sessionId: sessionId,
  deviceName: withMetadata ? deviceName : null,
  deviceType: withMetadata ? deviceType : null,
  platform: withMetadata ? platform : null,
  appVersion: withMetadata ? appVersion : null,
  ipAddress: withMetadata ? ipAddress : null,
  lastActivityAt: withMetadata
      ? (lastActivityAt ?? DateTime(2026, 9, 18, 21, 19))
      : null,
  createdAt: withMetadata ? (createdAt ?? DateTime(2026, 9, 1, 9)) : null,
);

/// In-memory sessions backend.
///
/// Revoked rows disappear from the next [fetchSessions], exactly like the real
/// `/shopkeeper/auth/sessions` list — so a test can prove the screen reloads
/// from the server instead of patching the row locally.
class FakeSessionsRepo implements SessionsRepository {
  FakeSessionsRepo({List<DeviceSession>? sessions, this.error, this.revokeError})
    : sessions = sessions ?? const <DeviceSession>[];

  List<DeviceSession> sessions;

  /// When set, thrown by [fetchSessions]. Mutable so a test can fail a load,
  /// clear it, and prove the Retry button actually recovers.
  Object? error;

  /// When set, thrown by [revokeSession].
  final Object? revokeError;

  int fetchCalls = 0;
  final List<String> revoked = [];

  @override
  Future<List<DeviceSession>> fetchSessions(String token) async {
    fetchCalls++;
    if (error != null) throw error!;
    return sessions
        .where((session) => !revoked.contains(session.sessionId))
        .toList(growable: false);
  }

  @override
  Future<void> revokeSession(String sessionId, String token) async {
    if (revokeError != null) throw revokeError!;
    revoked.add(sessionId);
  }
}

