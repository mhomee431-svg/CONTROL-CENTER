/// Lifecycle state of a customer account.
enum AccountStatus {
  active,
  pendingVerification,
  suspended;

  static AccountStatus fromApi(String? raw) {
    switch (raw) {
      case 'PENDING':
      case 'pending_verification':
      case 'pendingVerification':
        return AccountStatus.pendingVerification;
      case 'SUSPENDED':
      case 'suspended':
        return AccountStatus.suspended;
      default:
        return AccountStatus.active;
    }
  }
}

class UserProfile {
  final String id;
  final String name;
  final String email;
  final String phoneNumber;
  final String? avatarUrl;

  /// Lifecycle state reported by the backend; defaults to [AccountStatus.active]
  /// for local/demo profiles.
  final AccountStatus accountStatus;

  const UserProfile({
    required this.id,
    required this.name,
    required this.email,
    required this.phoneNumber,
    this.avatarUrl,
    this.accountStatus = AccountStatus.active,
  });

  UserProfile copyWith({
    String? name,
    String? email,
    String? phoneNumber,
    String? avatarUrl,
    AccountStatus? accountStatus,
  }) {
    return UserProfile(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      accountStatus: accountStatus ?? this.accountStatus,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is UserProfile &&
      other.id == id &&
      other.name == name &&
      other.email == email &&
      other.phoneNumber == phoneNumber &&
      other.avatarUrl == avatarUrl &&
      other.accountStatus == accountStatus;

  @override
  int get hashCode =>
      Object.hash(id, name, email, phoneNumber, avatarUrl, accountStatus);
}
