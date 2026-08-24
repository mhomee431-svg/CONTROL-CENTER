import '../domain/models/user_profile.dart';
import '../domain/profile_repository.dart';

/// Mock implementation of [ProfileRepository] for testing/development.
class MockProfileRepository implements ProfileRepository {
  /// Artificial latency; pass [Duration.zero] in widget tests running
  /// under fake-async time where real timers never fire.
  final Duration delay;

  UserProfile _current = const UserProfile(
    id: '1',
    name: 'Rahul Sharma',
    email: 'rahul.sharma@example.com',
    phoneNumber: '+91 98765 43210',
  );

  bool _deleted = false;

  MockProfileRepository({this.delay = const Duration(milliseconds: 200)});

  Future<void> _pause() async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
  }

  /// True after [deleteAccount] was called (test assertions only).
  bool get isDeleted => _deleted;

  @override
  Future<UserProfile> getProfile() async {
    await _pause();
    return _current;
  }

  @override
  Future<UserProfile> updateProfile({
    required String name,
    required String email,
    required String phoneNumber,
  }) async {
    await _pause();
    _current = _current.copyWith(
      name: name,
      email: email,
      phoneNumber: phoneNumber,
    );
    return _current;
  }

  @override
  Future<void> deleteAccount() async {
    await _pause();
    // Backend deletion isn't wired yet — record the intent so the
    // account-management flow is fully testable.
    _deleted = true;
  }
}
