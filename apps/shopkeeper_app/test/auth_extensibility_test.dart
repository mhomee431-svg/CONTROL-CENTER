import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/data/auth_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/data/mock_auth_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/domain/auth_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';

import 'fakes.dart';

/// Architecture-decision tests for the MVP authentication + account model:
///
///   AUTH  — Google Sign-In + Firebase Authentication is the ONLY active
///           method. Phone OTP is a future addition whose FUNCTION seam
///           (repository → controller, same /firebase-login exchange) is
///           already wired so the future UI needs no rewrite.
///
///   MODEL — ONE Firebase account → ONE user → ONE shopkeeper profile →
///           ONE shop. The shop list + selection notifier stay list-shaped
///           so business switching / multi-shop needs no model rewrite.
void main() {
  ProviderContainer makeContainer(FakeAuthRepository repo) {
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  group('AuthMethod decision (MVP = Google Sign-In + Firebase only)', () {
    test('Google + Firebase is the only MVP-active method', () {
      expect(AuthMethod.googleFirebase.isActiveInMvp, isTrue);
      expect(AuthMethod.phoneOtp.isActiveInMvp, isFalse);
      expect(AuthMethod.password.isActiveInMvp, isFalse);
    });
  });

  group('Phone OTP function seam (future UI plugs in here)', () {
    test('loginWithPhoneOtp exchanges the token on the SAME contract as '
        'Google and authenticates', () async {
      final fake = FakeAuthRepository()..restoreResult = makeSession();
      final container = makeContainer(fake);

      final ok = await container
          .read(authControllerProvider.notifier)
          .loginWithPhoneOtp(firebaseIdToken: 'mock-phone-otp-id-token');

      expect(ok, isTrue);
      // The OTP path routes through the identical /firebase-login exchange —
      // that is the whole no-rewrite guarantee.
      expect(fake.firebaseLoginCalls, 1);

      final auth = container.read(authControllerProvider);
      expect(auth.status, AuthStatus.authenticated);
      expect(auth.user, isNotNull);
      // Single-shop model: the authorized shop is auto-selected.
      expect(container.read(selectedShopProvider), isNotNull);
    });

    test('restricted account via OTP lands on the account-restricted state',
        () async {
      final fake = FakeAuthRepository()
        ..restoreResult = makeRestrictedSession(status: 'SUSPENDED');
      final container = makeContainer(fake);

      final ok = await container
          .read(authControllerProvider.notifier)
          .loginWithPhoneOtp(firebaseIdToken: 'mock-phone-otp-id-token');

      expect(ok, isFalse);
      expect(container.read(authControllerProvider).status,
          AuthStatus.accountRestricted);
    });

    test('backend failure surfaces the readable error', () async {
      final fake = FakeAuthRepository()
        ..submitError = const ApiException(
            statusCode: 401, message: 'Invalid Firebase token.');
      final container = makeContainer(fake);

      final ok = await container
          .read(authControllerProvider.notifier)
          .loginWithPhoneOtp(firebaseIdToken: 'bad-token');

      expect(ok, isFalse);
      final auth = container.read(authControllerProvider);
      expect(auth.status, AuthStatus.error);
      expect(auth.errorMessage, 'Invalid Firebase token.');
    });

    test('MockAuthRepository OTP path delegates to the Google exchange '
        '(offline-dev parity)', () async {
      final tokens = InMemoryTokenStore();
      final mock = MockAuthRepository(tokens);

      final session = await mock.loginWithPhoneOtp(
        firebaseIdToken: 'mock-phone-otp-id-token',
      );

      expect(session.user.name, 'Test Shopkeeper');
      expect(await tokens.readAccessToken(), isNotNull);
    });
  });

  group('Business switching function (future multi-shop entry point)', () {
    test('switches to an authorized shop and updates the selection',
        () async {
      final fake = FakeAuthRepository()
        ..restoreResult =
            makeSession(shops: [ownerShop(id: 10), managerShop(id: 20)]);
      final container = makeContainer(fake);

      // Sign in → primary (first) shop auto-selected.
      await container.read(authControllerProvider.notifier).checkSession();
      expect(container.read(selectedShopProvider)?.id, 10);

      final switched = container
          .read(authControllerProvider.notifier)
          .selectBusiness(managerShop(id: 20));

      expect(switched, isTrue);
      expect(container.read(selectedShopProvider)?.id, 20);
      expect(container.read(selectedShopProvider)?.isManager, isTrue);
    });

    test('rejects a shop the backend never authorized', () async {
      final fake = FakeAuthRepository()..restoreResult = makeSession();
      final container = makeContainer(fake);
      await container.read(authControllerProvider.notifier).checkSession();

      final stranger = ownerShop(id: 999, name: 'Not Mine');
      final switched = container
          .read(authControllerProvider.notifier)
          .selectBusiness(stranger);

      expect(switched, isFalse);
      // Selection unchanged — the client never self-authorizes a switch.
      expect(container.read(selectedShopProvider)?.id, 10);
    });
  });

  group('Account model (ONE account → ONE profile → ONE shop, extensible)',
      () {
    test('ShopSummary exposes the owner/manager role helpers', () {
      expect(ownerShop().isOwner, isTrue);
      expect(ownerShop().isManager, isFalse);
      expect(managerShop().isManager, isTrue);
      expect(managerShop().isOwner, isFalse);
    });

    test('shops stay a list — multiple authorized shops survive the session',
        () async {
      final fake = FakeAuthRepository()
        ..restoreResult =
            makeSession(shops: [ownerShop(id: 10), managerShop(id: 20)]);
      final container = makeContainer(fake);

      await container.read(authControllerProvider.notifier).checkSession();

      final auth = container.read(authControllerProvider);
      expect(auth.status, AuthStatus.authenticated);
      expect(auth.shops, hasLength(2));
      // MVP behavior: the FIRST shop is primary; the rest stay available
      // for the future business-switching UI.
      expect(container.read(selectedShopProvider)?.id, 10);
    });
  });
}
