import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/features/auth/presentation/controllers/post_login_destination.dart';

void main() {
  group('post-login destination', () {
    test('starts empty, so a customer who began at Welcome lands on Home', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(postLoginDestinationProvider), isNull);
    });

    test('records a real page so sign-in can return to it', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(postLoginDestinationProvider.notifier)
          .set('/saved?tab=products');

      expect(
        container.read(postLoginDestinationProvider),
        '/saved?tab=products',
      );
    });

    test('take() clears as it reads, so a later sign-in is not hijacked', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(postLoginDestinationProvider.notifier);

      notifier.set('/saved');
      expect(notifier.take(), '/saved');

      // The whole point of `take`: consumed exactly once, so signing in again
      // later starts from Home instead of a page from the previous session.
      expect(container.read(postLoginDestinationProvider), isNull);
      expect(notifier.take(), isNull);
    });
  });
}