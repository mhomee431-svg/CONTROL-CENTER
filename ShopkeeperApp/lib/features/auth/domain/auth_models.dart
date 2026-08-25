/// Core identity models for the Shopkeeper App.
class ShopkeeperUser {
  const ShopkeeperUser({
    required this.id,
    required this.phoneNumber,
    this.name,
    this.email,
    this.role,
  });

  final int id;
  final String phoneNumber;
  final String? name;
  final String? email;
  final String? role;

  factory ShopkeeperUser.fromJson(Map<String, dynamic> json) =>
      ShopkeeperUser(
        id: (json['id'] as num?)?.toInt() ?? 0,
        phoneNumber: json['phone_number'] as String? ?? '',
        name: json['name'] as String?,
        email: json['email'] as String?,
        role: json['role'] as String?,
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
