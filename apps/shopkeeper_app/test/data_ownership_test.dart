import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/data/auth_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/dashboard/data/dashboard_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/data/inventory_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/data/import_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/notifications/data/notifications_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/data/product_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/presentation/controllers/products_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/data/shop_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/domain/shop_models.dart';

import 'fakes.dart';

/// DATA OWNERSHIP — Firebase identity ⇒ backend application user ⇒
/// shopkeeper profile ⇒ single business/shop.
///
/// The chain is literal:
///
///   1. The device proves Firebase identity (Google sign-in → ID token).
///   2. The backend verifies the token and returns its OWN application user
///      (access + refresh pair) — the Firebase token is never used as API
///      authorization again.
///   3. From that moment every API call carries ONLY the backend bearer token,
///      and every shop-scoped call additionally names the selected business.
///
/// This file is the Flutter-side tripwire for that rule. Each assertion was
/// checked against a deliberately-injected violation.
void main() {
  ProviderContainer makeContainer({
    FakeAuthRepository? auth,
    FakeShopRepo? shops,
    FakeDashboardRepo? dashboard,
    FakeProductRepo? products,
    ShopSummary? selected,
  }) {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          auth ?? (FakeAuthRepository()..restoreResult = makeSession()),
        ),
        shopRepositoryProvider.overrideWithValue(shops ?? FakeShopRepo()),
        tokenStoreProvider.overrideWithValue(
          InMemoryTokenStore(accessToken: 'test-access-token'),
        ),
        dashboardRepositoryProvider.overrideWithValue(
          dashboard ?? FakeDashboardRepo(),
        ),
        inventoryRepositoryProvider.overrideWithValue(
          products ?? FakeProductRepo(),
        ),
        productRepositoryProvider.overrideWithValue(
          products ?? FakeProductRepo(),
        ),
        // DashboardController._loadAlerts() derives low-stock alerts from the
        // import + product repos. Without this override they perform REAL HTTP
        // inside a plain test() (no binding) and hang ~30s.
        inventoryImportRepositoryProvider.overrideWithValue(FakeImportRepo()),
        // …and reads the unread count from the notifications repo. Same rule:
        // a plain test() must never open a socket.
        notificationsRepositoryProvider.overrideWithValue(
          FakeNotificationsRepo(),
        ),
        if (selected != null)
          selectedShopProvider.overrideWith(
            () => SelectedShopOverride(selected),
          ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('ownership layer 1 — Firebase identity is exchanged ONCE', () {
    test(
      'the session restore uses the stored backend token, never Firebase',
      () async {
        final auth = FakeAuthRepository()..restoreResult = makeSession();
        final container = makeContainer(auth: auth);
        await container.read(authControllerProvider.notifier).checkSession();

        // `restoreSession` (stored backend JWT → /me) ran the start-up — the
        // Firebase exchange was never reached on this path.
        expect(auth.firebaseLoginCalls, 0);
        // The session that comes back is the BACKEND application user.
        expect(container.read(authControllerProvider).user?.id, 1);
      },
    );

    test('the stored backend token is still the one the app holds', () async {
      final auth = FakeAuthRepository()..restoreResult = makeSession();
      final container = makeContainer(auth: auth);
      await container.read(authControllerProvider.notifier).checkSession();

      // One start-up, one clean restore — and the backend token the restore
      // READ is still the single token the store holds (single source).
      expect(auth.firebaseLoginCalls, 0);
      expect(
        await container.read(tokenStoreProvider).readAccessToken(),
        'test-access-token',
      );
    });
  });

  group('ownership layer 2 — no bearer token, no API call', () {
    test('products refuse to load when the store has no token', () async {
      final products = FakeProductRepo();
      final container = makeContainer(
        products: products,
        selected: ownerShop(),
      );
      // Empty store ⇒ refused before any network: the shop IS owned, the
      // bearer identity is not — and the repository is never touched.
      await container.read(tokenStoreProvider).clearAll();
      await container.read(productsControllerProvider.notifier).load();

      expect(products.overviewCalls, 0);
      expect(
        container.read(productsControllerProvider).message,
        contains('signed in'),
      );
    });

    test('dashboard refuses to load when the store has no token', () async {
      final dashboard = FakeDashboardRepo();
      final container = makeContainer(
        dashboard: dashboard,
        selected: ownerShop(),
      );
      await container.read(tokenStoreProvider).clearAll();
      await container.read(dashboardControllerProvider.notifier).load();

      expect(dashboard.calls, 0);
    });
  });

  group('ownership layer 3 — every shop call names the selected business', () {
    test('products load is scoped to the selected shop id', () async {
      final products = FakeProductRepo();
      final container = makeContainer(
        products: products,
        selected: ownerShop(id: 10),
      );

      await container.read(productsControllerProvider.notifier).load();

      expect(products.lastShopId, 10);
      expect(products.overviewCalls, 1);
    });

    test('dashboard load is scoped to the selected shop id', () async {
      final dashboard = FakeDashboardRepo();
      final container = makeContainer(
        dashboard: dashboard,
        selected: ownerShop(id: 10),
      );

      await container.read(dashboardControllerProvider.notifier).load();

      expect(dashboard.lastShopId, 10);
      expect(dashboard.calls, 1);
    });

    test(
      'a selection change re-scopes the next load (no stale id reuse)',
      () async {
        final products = FakeProductRepo();
        final container = makeContainer(
          products: products,
          selected: ownerShop(id: 10),
        );

        await container.read(productsControllerProvider.notifier).load();
        expect(products.lastShopId, 10);

        // The shopkeeper's business changes (future multi-shop / re-register) —
        // the NEXT load must carry the NEW id, never the cached one.
        container.read(selectedShopProvider.notifier).select(ownerShop(id: 99));
        await container.read(productsControllerProvider.notifier).load();
        expect(products.lastShopId, 99);
      },
    );

    test('no selection ⇒ no call: ownership can never be unscoped', () async {
      final products = FakeProductRepo();
      final container = makeContainer(
        products: products,
        selected: ownerShop(),
      );
      // The session means business — clearing the SELECTION makes the id
      // unresolvable, so the controller must refuse instead of guessing.
      container.read(selectedShopProvider.notifier).select(null);
      await container.read(productsControllerProvider.notifier).load();

      expect(products.overviewCalls, 0);
      expect(
        container.read(productsControllerProvider).message,
        'No shop selected',
      );
    });
  });

  group('ownership layer 4 — source scan: the ownership shape', () {
    test('no feature file bypasses the bearer-token channels', () {
      final offenders = <String>[];
      for (final file
          in Directory('lib/features')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          // A hand-rolled Authorization header outside the two sanctioned
          // shapes (ApiClient._options / the import repo's multipart path)
          // would send SOME token the refresh/watch path cannot rotate.
          if (line.contains("'Authorization'") &&
              !file.path.endsWith('api_client.dart') &&
              !file.path.endsWith('import_repository.dart')) {
            offenders.add('${file.path}:${i + 1}: ${line.trim()}');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'Every backend call must travel through ApiClient (bearer '
            'header + 401 refresh) or the audited multipart import path. '
            'Dio must not be driven raw from a feature file.\n'
            '${offenders.join('\n')}',
      );
    });

    test('the lib directory resolved (guards against a silent empty scan)', () {
      expect(
        Directory('lib').existsSync(),
        isTrue,
        reason: 'run from apps/shopkeeper_app',
      );
    });

    test('no log line prints a fragment of a live credential', () {
      // Ownership includes not letting the identity leave the process by
      // another door. `debugPrint` is NOT assert-gated — it still runs in a
      // RELEASE build, so a token substring lands in the device log and any
      // attached crash report.
      //
      // The whole auth chain already follows "length only"
      // (`firebase_auth_service.dart`, `auth_repository.firebaseLogin`); a
      // single line in `auth_controller` printed the first 30 characters of a
      // live Firebase ID token, which is why this rule is enforced by scan
      // rather than left to review.
      final offenders = <String>[];
      for (final file
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (!(line.contains('debugPrint') || line.contains('print('))) {
            continue;
          }
          // Interpolating a credential identifier into a log is the leak.
          final leaksValue = RegExp(
            r'(idToken|accessToken|refreshToken|firebaseIdToken|jwtToken|'
            r'apiKey|apiSecret)',
          ).hasMatch(line);
          if (!leaksValue) continue;
          // …unless the line is demonstrably about the token's SIZE, its
          // PRESENCE, or the plumbing (reads/writes/params), not its value.
          final safe = RegExp(
            r'length|chars|present|null|isEmpty|!=|==|readAccessToken|'
            r'readRefreshToken|writeAccessToken|writeRefreshToken|clearAll|'
            r'tokenStore|token:\s*|final\s+\w*[Tt]oken|required|String\s+\w*[Tt]oken',
          ).hasMatch(line);
          if (safe) continue;
          offenders.add('${file.path}:${i + 1}: ${line.trim()}');
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'A log line interpolates a credential VALUE. Log its length '
            'or presence instead — the token never belongs in a log line.\n'
            '${offenders.join('\n')}',
      );
    });
  });
}
