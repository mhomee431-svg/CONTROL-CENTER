class UserProfile {
  final String id;
  final String name;
  final String email;
  final String phoneNumber;
  final String? avatarUrl;

  const UserProfile({
    required this.id,
    required this.name,
    required this.email,
    required this.phoneNumber,
    this.avatarUrl,
  });

  UserProfile copyWith({
    String? name,
    String? email,
    String? phoneNumber,
    String? avatarUrl,
  }) {
    return UserProfile(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }
}