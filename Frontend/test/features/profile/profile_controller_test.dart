import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_customer_app/features/profile/presentation/controllers/profile_controller.dart';

void main() {
  group('ProfileController', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state has mock profile data', () {
      final profile = container.read(profileControllerProvider);
      expect(profile, isNotNull);
      expect(profile!.name, 'Rahul Sharma');
      expect(profile.email, 'rahul.sharma@example.com');
      expect(profile.phoneNumber, '+91 98765 43210');
    });

    test('updateProfile updates fields correctly', () {
      final controller = container.read(profileControllerProvider.notifier);
      controller.updateProfile(
        name: 'Priya Verma',
        email: 'priya@example.com',
        phoneNumber: '+91 99887 76655',
      );

      final profile = container.read(profileControllerProvider);
      expect(profile!.name, 'Priya Verma');
      expect(profile.email, 'priya@example.com');
      expect(profile.phoneNumber, '+91 99887 76655');
    });

    test('logout sets state to null', () {
      final controller = container.read(profileControllerProvider.notifier);
      expect(container.read(profileControllerProvider), isNotNull);

      controller.logout();

      expect(container.read(profileControllerProvider), isNull);
    });
  });
}