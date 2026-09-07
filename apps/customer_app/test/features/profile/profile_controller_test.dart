import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_customer_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:hyperlocal_customer_app/features/profile/data/mock_profile_repository.dart';
import 'package:hyperlocal_customer_app/features/profile/domain/models/user_profile.dart';
import 'package:hyperlocal_customer_app/features/profile/presentation/controllers/profile_controller.dart';

/// Pins the auth controller to a fixed status so profile loading can be
/// exercised for each account state.
class _StubAuthController extends AuthController {
  final AuthStatus status;
  _StubAuthController(this.status);

  @override
  AuthState build() => AuthState(status: status);
}

ProviderContainer _container(
  MockProfileRepository repository,
  AuthStatus authStatus,
) {
  return ProviderContainer(
    overrides: [
      profileRepositoryProvider.overrideWithValue(repository),
      authControllerProvider.overrideWith(() => _StubAuthController(authStatus)),
    ],
  );
}

void main() {
  group('ProfileController', () {
    late MockProfileRepository repository;

    setUp(() {
      repository = MockProfileRepository(delay: Duration.zero);
    });

    /// Waits until the initial load settles.
    Future<void> waitLoaded(ProviderContainer container) async {
      container.read(profileControllerProvider.notifier);
      for (var i = 0; i < 200; i++) {
        final state = container.read(profileControllerProvider);
        if (!state.isLoading && !state.isRefreshing) return;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    test('authenticated user gets the mock profile with active account state',
        () async {
      final container = _container(repository, AuthStatus.authenticated);
      addTearDown(container.dispose);

      await waitLoaded(container);

      final profile = container.read(profileControllerProvider).value;
      expect(profile, isNotNull);
      expect(profile!.name, 'Rahul Sharma');
      expect(profile.email, 'rahul.sharma@example.com');
      expect(profile.phoneNumber, '+91 98765 43210');
      expect(profile.accountStatus, AccountStatus.active);
    });

    test('guests get no server profile (null state)', () async {
      final container = _container(repository, AuthStatus.guest);
      addTearDown(container.dispose);

      await waitLoaded(container);

      expect(container.read(profileControllerProvider).value, isNull);
    });

    test('signed-out users get a null profile', () async {
      final container = _container(repository, AuthStatus.unauthenticated);
      addTearDown(container.dispose);

      await waitLoaded(container);

      expect(container.read(profileControllerProvider).value, isNull);
    });

    test('updateProfile persists edits and reports success', () async {
      final container = _container(repository, AuthStatus.authenticated);
      addTearDown(container.dispose);
      await waitLoaded(container);
      final controller = container.read(profileControllerProvider.notifier);

      final ok = await controller.updateProfile(
        name: 'Priya Verma',
        email: 'priya@example.com',
        phoneNumber: '+91 99887 76655',
      );

      expect(ok, isTrue);
      final profile = container.read(profileControllerProvider).value!;
      expect(profile.name, 'Priya Verma');
      expect(profile.email, 'priya@example.com');
      expect(profile.phoneNumber, '+91 99887 76655');
    });

    test('deleteAccount clears local state and records deletion', () async {
      final container = _container(repository, AuthStatus.authenticated);
      addTearDown(container.dispose);
      await waitLoaded(container);
      expect(container.read(profileControllerProvider).value, isNotNull);

      final ok =
          await container.read(profileControllerProvider.notifier).deleteAccount();

      expect(ok, isTrue);
      expect(repository.isDeleted, isTrue);
      expect(container.read(profileControllerProvider).value, isNull);
    });
  });
}
