/// Core identity models for the Shopkeeper App.
class ShopkeeperUser {
  const ShopkeeperUser({
    required this.id,
    required this.phoneNumber,
    this.name,
    this.email,
    this.role,
    this.businessId,
    this.avatarUrl,
    this.status,
    this.isShopkeeper,
  });

  final int id;
  final String phoneNumber;
  final String? name;
  final String? email;
  final String? role;
  final String? businessId;
  final String? avatarUrl;

  /// Backend lifecycle status (ACTIVE / INACTIVE / SUSPENDED / BANNED).
  /// Surfaced at startup so restricted accounts land on the account-status
  /// screen instead of the normal app (Phase 23).
  final String? status;

  /// ─ SHOPKEEPER ACCESS (tri-state — do not collapse to bool) ─────────────
  ///
  /// `true`  → backend confirmed SHOPKEEPER access (shop owner/manager).
  /// `false` → backend confirmed this is a NON-shopkeeper account.
  /// `null`  → UNKNOWN — the endpoint that produced this user never reported
  ///           the flag.
  ///
  /// This MUST stay nullable. `POST /shopkeeper/auth/firebase-login` does not
  /// include `is_shopkeeper` in its response (its `_build_login_response`
  /// carries only `role`), while `GET /auth/me` does. Treating "absent" as
  /// `false` would lock every valid shopkeeper out of the app the moment they
  /// sign in, so `null` is resolved as PERMISSIVE everywhere.
  final bool? isShopkeeper;

  factory ShopkeeperUser.fromJson(Map<String, dynamic> json) =>
      ShopkeeperUser(
        id: (json['id'] as num?)?.toInt() ?? 0,
        phoneNumber: json['phone_number'] as String? ?? '',
        name: json['name'] as String?,
        email: json['email'] as String?,
        role: json['role'] as String?,
        businessId: json['business_id'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        status: json['status'] as String?,
        // Tri-state: absent stays `null` (unknown → permissive), never false.
        // Only an explicit backend `false` denies shopkeeper access.
        isShopkeeper: json['is_shopkeeper'] as bool?,
      );

  String get displayName => (name != null && name!.trim().isNotEmpty)
      ? name!.trim()
      : phoneNumber;
}

/// A shop the signed-in user is authorized to manage (owner or manager),
/// including the effective permission keys granted by the backend.
class ShopSummary {
  const ShopSummary({
    required this.id,
    required this.name,
    required this.status,
    required this.isVerified,
    required this.membership,
    required this.permissions,
    this.category,
    this.imageUrl,
  });

  final int id;
  final String name;
  final String status;
  final bool isVerified;
  final String? category;
  final String? imageUrl;

  /// `owner` | `manager`
  final String membership;

  /// Effective permission keys, e.g. `update:shop`, `create:product`.
  final List<String> permissions;

  bool get isOwner => membership == 'owner';
  bool get isManager => membership == 'manager';

  bool get canManageSettings => permissions.contains('update:shop');
  bool get canManageProducts => permissions.contains('update:product');

  factory ShopSummary.fromJson(Map<String, dynamic> json) => ShopSummary(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        status: json['status'] as String? ?? 'REGISTERED',
        isVerified: json['is_verified'] as bool? ?? false,
        category: json['category'] as String?,
        imageUrl: json['image_url'] as String?,
        membership: json['membership'] as String? ?? 'manager',
        permissions: (json['permissions'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(growable: false),
      );
}

/// Result of a successful login / registration / session restore.
class AuthSession {
  const AuthSession({required this.user, required this.shops});

  final ShopkeeperUser user;
  final List<ShopSummary> shops;
}

/// ── AUTHENTICATION DECISION (MVP) ─────────────────────────────────────────
///
/// MVP ships with EXACTLY ONE sign-in method:
///
///     Google Sign-In  →  Firebase Authentication  →  Firebase ID token
///       →  backend `/shopkeeper/auth/firebase-login` (Admin-SDK verified)
///       →  app session (backend-issued JWT pair).
///
/// NOT in the MVP (repository functions exist; UI is intentionally absent):
///   * Phone OTP / SMS OTP / custom OTP service
///   * Password authentication
///   * Custom JWT login system
///
/// Phone-OTP extension path (no rewrite required):
///   Firebase issues ONE ID-token shape regardless of provider. A future
///   Phone-OTP UI obtains the token via
///   `FirebaseAuth.signInWithPhoneNumber` → confirmation → `getIdToken()`,
///   then calls [AuthRepository.loginWithPhoneOtp] — which exchanges the
///   token on the SAME `/firebase-login` endpoint used by Google today.
///   Nothing below the [AuthRepository] contract changes.
enum AuthMethod {
  /// MVP: Google Sign-In + Firebase Authentication (the ONLY active method).
  googleFirebase,

  /// FUTURE: Firebase Phone Auth (SMS OTP). Function seam already wired
  /// through [AuthRepository.loginWithPhoneOtp]; UI comes later.
  phoneOtp,

  /// FUTURE: password authentication (repository functions exist; the
  /// /register, /forgot-password and /reset-password routes are NOT linked
  /// from the Google-only flow).
  password,
}

extension AuthMethodMvp on AuthMethod {
  /// True only for methods active in the current MVP.
  bool get isActiveInMvp => this == AuthMethod.googleFirebase;
}

