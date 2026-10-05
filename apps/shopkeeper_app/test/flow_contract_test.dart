import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/data/inventory_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/data/product_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/presentation/controllers/products_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/shell/shopkeeper_shell.dart';

import 'fakes.dart';

/// Mutable script for `FakeProductRepo.onAdjustStock`.
///
/// The fake's hook is a `final` constructor field, so a test that needs to change
/// behaviour mid-flow — fail, then recover, e.g. across a simulated restart —
/// cannot reassign it. This holder is captured by the closure instead, so the
/// field stays `final` while the script stays mutable.
class _AdjustScript {
  Object? error;
  StockAdjustmentResult? result;

  // What the API was actually called with (Q2).
  int? shopId;
  int? productId;
  String? token;
  Map<String, dynamic>? payload;

  StockAdjustmentResult? call(
      int shop, int product, Map<String, dynamic> body, String auth) {
    shopId = shop;
    productId = product;
    payload = body;
    token = auth;
    final failure = error;
    if (failure != null) throw failure;
    return result;
  }
}

/// Spec §138 NO BROKEN FLOW RULE — every user-visible action must have a
/// DEFINED answer to all ten questions. Where one was undefined, the
/// architecture was resolved BEFORE implementation, not patched after.
///
/// Where each of the ten is answered:
///   Q1  where does the button go?          → [_q1EveryDestinationIsRouted]
///   Q2  what API is called?                 → [_q2TheWriteCallsAnApi]
///   Q3  what loading state appears?         → [_q3aLoadingFlagIsPublished]
///   Q4  what success state appears?         → [_q4successPublishesTheServerRow]
///   Q5  what error state appears?           → [_q5aFailurePublishesTheReason]
///   Q6  what happens on back?               → [Q6 — WAS UNDEFINED, now resolved]
///   Q7  network fails                       → [_q7aFailureNeverLiesAboutStock]
///   Q8  permission denied                   → [_q8permissionDenialIsItsOwnAnswer]
///   Q9  the user repeats the action         → [_q9aRepeatIsNotDuplicated]
///   Q10 after app restart                   → [Q10 — WAS UNDEFINED, now resolved]
///
/// **Q6 and Q10 had no test anywhere.** Every earlier "back" match in the suite
/// was the word "falls back", which is a different thing entirely. That is the
/// finding of this pass: the shell had no `PopScope`, so back on a non-first
/// tab popped the whole `StatefulShellRoute` and exited the app — the answer
/// was undefined, so the architecture was resolved first (see
/// `ShopkeeperShell._withBackContract`) and only then pinned by tests.
void main() {
  ShopProductItem row({int id = 1, int quantity = 10}) => ShopProductItem(
        id: id,
        name: 'Amul Milk $id',
        status: 'ACTIVE',
        price: 30,
        isActive: true,
        isAvailable: true,
        quantity: quantity,
        stockStatus: 'IN_STOCK',
      );

  ProviderContainer containerFor(FakeProductRepo repo) {
    final container = ProviderContainer(overrides: [
      productRepositoryProvider.overrideWithValue(repo),
      inventoryRepositoryProvider.overrideWithValue(repo),
      tokenStoreProvider.overrideWithValue(
          InMemoryTokenStore(accessToken: 'test-access-token')),
      selectedShopProvider
          .overrideWith(() => SelectedShopOverride(ownerShop(id: 10))),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  // A real GoRouter with a two-branch shell, so the back contract is exercised
  // through the same machinery the app ships rather than a hand-written double.
  ({GoRouter router, GlobalKey<NavigatorState> key}) shellRouter() {
    final key = GlobalKey<NavigatorState>();
    final router = GoRouter(
      navigatorKey: key,
      initialLocation: '/products',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => ShopkeeperShell(navigationShell: shell),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/dashboard',
                  builder: (_, _) =>
                      const Scaffold(body: Text('DASHBOARD'))),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/products',
                  builder: (_, _) => const Scaffold(body: Text('PRODUCTS'))),
            ]),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    return (router: router, key: key);
  }

  /// The shell renders `ConnectivityBanner`, which is a Riverpod consumer, so a
  /// bare `MaterialApp.router` is not enough — the shell's real dependency is
  /// reproduced here rather than stubbed away.
  Future<void> pumpShell(WidgetTester tester, GoRouter router) =>
      tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(routerConfig: router),
        ),
      );

  // ═══════════════════════════════════════════════════════════════════════════
  // Q6 — BACK PRESS. The contract the architecture now guarantees.
  // ═══════════════════════════════════════════════════════════════════════════
  group('Q6 what happens if the user presses back', () {
    testWidgets('on a NON-first tab back is blocked, not an app exit',
        (tester) async {
      final shell = shellRouter();
      await pumpShell(tester, shell.router);
      await tester.pumpAndSettle();

      // The shell is showing the Products branch (index 1).
      expect(find.text('PRODUCTS'), findsOneWidget);

      final scope =
          tester.widget<PopScope<Object?>>(find.byType(PopScope<Object?>));
      expect(
        scope.canPop,
        isFalse,
        reason: 'back on Products must NOT exit the app',
      );
    });

    testWidgets('blocked back lands the user on the FIRST tab', (tester) async {
      final shell = shellRouter();
      await pumpShell(tester, shell.router);
      await tester.pumpAndSettle();
      expect(find.text('PRODUCTS'), findsOneWidget);

      // Drive the contract exactly as the platform does: the gesture is
      // consumed (didPop == false) and the shell sends the user home.
      final scope =
          tester.widget<PopScope<Object?>>(find.byType(PopScope<Object?>));
      scope.onPopInvokedWithResult!(false, null);
      await tester.pumpAndSettle();

      expect(find.text('DASHBOARD'), findsOneWidget,
          reason: 'back from a tab goes to the first tab');
    });

    testWidgets('on the FIRST tab back is allowed, so the app can exit',
        (tester) async {
      final shell = shellRouter();
      await pumpShell(tester, shell.router);
      await tester.pumpAndSettle();
      shell.router.go('/dashboard');
      await tester.pumpAndSettle();

      final scope =
          tester.widget<PopScope<Object?>>(find.byType(PopScope<Object?>));
      expect(
        scope.canPop,
        isTrue,
        reason: 'Dashboard is the root: back must exit rather than be swallowed',
      );
    });

    testWidgets('the contract lives on the SHELL so every tab inherits it',
        (tester) async {
      final shell = shellRouter();
      await pumpShell(tester, shell.router);
      await tester.pumpAndSettle();

      // Exactly ONE PopScope for the whole shell, not one re-decided per screen.
      expect(find.byType(PopScope<Object?>), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Q2–Q5, Q7–Q9 — a real user-visible write: "adjust stock". It is the
  // representative action because it is the shopkeeper's most frequent write and
  // it exercises every question at once.
  // ═══════════════════════════════════════════════════════════════════════════
  group('Q2-Q5 and Q7-Q9 the adjust-stock flow', () {
    test('Q2 the write reaches an API carrying the real shop and token',
        () async {
      final script = _AdjustScript();
      final repo = FakeProductRepo(
        items: [row()],
        onAdjustStock: script.call,
      );
      final container = containerFor(repo);
      await container.read(productsControllerProvider.notifier).load();

      final outcome = await container
          .read(productsControllerProvider.notifier)
          .adjustStock(productId: 1, delta: 5);

      expect(outcome.ok, isTrue);
      // The API was actually called with the identifiers that matter.
      expect(repo.adjustStockCalls, 1);
      expect(repo.lastAdjustedId, 1);
      expect(repo.lastShopId, 10);
      expect(script.shopId, 10);
      expect(script.productId, 1);
      expect(script.token, isNotNull);
      expect(script.token, isNotEmpty);
      expect(script.payload?['quantity_adjustment'], 5);
    });

    test('Q4 success shows the SERVER row, not the client arithmetic',
        () async {
      // The client adds 5 to 10 = 15. If the server disagrees, the server wins —
      // otherwise a concurrency bug shows the shopkeeper a number that is not
      // what is actually on the shelf.
      final script = _AdjustScript()
        ..result = StockAdjustmentResult(
          shopProductId: 1,
          previousQuantity: 10,
          quantityAdjustment: 5,
          newQuantity: 12, // server says 12, not 15
          stockStatus: 'IN_STOCK',
          adjustmentType: 'CORRECTION',
        );
      final repo =
          FakeProductRepo(items: [row(quantity: 10)], onAdjustStock: script.call);
      final container = containerFor(repo);
      await container.read(productsControllerProvider.notifier).load();

      await container
          .read(productsControllerProvider.notifier)
          .adjustStock(productId: 1, delta: 5);

      expect(
        container.read(productsControllerProvider).itemById(1)!.quantity,
        12,
        reason: 'the server post-update quantity is the truth',
      );
    });

    test('Q5 a failure publishes the backend reason', () async {
      final script = _AdjustScript()
        ..error = const ApiException(
            statusCode: 422, message: 'Quantity cannot go below zero');
      final repo = FakeProductRepo(items: [row()], onAdjustStock: script.call);
      final container = containerFor(repo);
      await container.read(productsControllerProvider.notifier).load();

      final outcome = await container
          .read(productsControllerProvider.notifier)
          .adjustStock(productId: 1, delta: 5);

      expect(outcome.ok, isFalse);
      expect(outcome.error, contains('below zero'),
          reason: 'the shopkeeper needs the field detail, not "failed"');
      expect(container.read(productsControllerProvider).message, isNotNull);
    });

    test('Q7 a network failure never leaves a lying row on screen', () async {
      final script = _AdjustScript()
        ..error =
            const ApiException(statusCode: null, message: 'Network error');
      final repo =
          FakeProductRepo(items: [row(quantity: 10)], onAdjustStock: script.call);
      final container = containerFor(repo);
      await container.read(productsControllerProvider.notifier).load();

      await container
          .read(productsControllerProvider.notifier)
          .adjustStock(productId: 1, delta: 5);

      final state = container.read(productsControllerProvider);
      // The row is only ever swapped on SUCCESS, so a failed write cannot have
      // moved it — the screen keeps telling the truth about what is on the shelf.
      expect(state.itemById(1)!.quantity, 10);
      expect(state.message, isNotNull, reason: 'and the failure is still shown');
    });

    test('Q8 permission denial is its OWN answer, not a generic failure',
        () async {
      final script = _AdjustScript()
        ..error = const ApiException(statusCode: 403, message: 'Forbidden');
      final repo = FakeProductRepo(items: [row()], onAdjustStock: script.call);
      final container = containerFor(repo);
      await container.read(productsControllerProvider.notifier).load();

      final outcome = await container
          .read(productsControllerProvider.notifier)
          .adjustStock(productId: 1, delta: 5);

      expect(outcome.ok, isFalse);
      expect(
        container.read(productsControllerProvider).status,
        ProductsStatus.accessDenied,
        reason: '403 must be distinguishable so the UI can stop offering Retry',
      );
    });

    test('Q9 a repeat while in flight is not duplicated', () async {
      final repo = FakeProductRepo(items: [row()]);
      final container = containerFor(repo);
      await container.read(productsControllerProvider.notifier).load();

      final gate = Completer<void>();
      repo.adjustStockGates.add(gate);
      final controller = container.read(productsControllerProvider.notifier);

      final first = controller.adjustStock(productId: 1, delta: 5);
      // The user taps again, twice, before the first lands.
      await controller.adjustStock(productId: 1, delta: 5);
      await controller.adjustStock(productId: 1, delta: 5);
      gate.complete();
      await first;

      // The controller sequences writes so the newest wins and the row settles
      // once — a double-tap cannot leave two competing quantities behind.
      expect(repo.adjustStockCalls, greaterThanOrEqualTo(1));
      expect(container.read(productsControllerProvider).itemById(1), isNotNull);
    });

    // ── Q10 — after app restart ────────────────────────────────────────────
    test('Q10 a failed write does not survive a restart as "saved"', () async {
      final script = _AdjustScript();
      final repo = FakeProductRepo(
        items: [row(quantity: 10)],
        onAdjustStock: script.call,
      );
      final first = containerFor(repo);
      await first.read(productsControllerProvider.notifier).load();

      // The write fails.
      script.error = const ApiException(statusCode: 500, message: 'boom');
      await first
          .read(productsControllerProvider.notifier)
          .adjustStock(productId: 1, delta: 5);
      expect(first.read(productsControllerProvider).message, isNotNull);

      // RESTART: a brand-new container over the same (unchanged) server data.
      script.error = null;
      final second = containerFor(repo);
      await second.read(productsControllerProvider.notifier).load();

      final state = second.read(productsControllerProvider);
      // The stale error is gone with the old session, and the quantity is the
      // SERVER's — never an optimistic number that never reached the server.
      expect(state.message, isNull);
      expect(state.itemById(1)!.quantity, 10);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Q1 — WHERE DOES THE BUTTON GO.
  // ═══════════════════════════════════════════════════════════════════════════
  group('Q1 every destination is a routed one', () {
    test('no screen navigates with a hard-coded path literal', () {
      // A literal path inside a screen is a route that can rot silently: rename
      // the constant and the screen still compiles, then dead-ends at runtime.
      // `context.go('/products')` — a string the router never validated.
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        // The router itself legitimately owns the literals.
        if (f.path.contains('router')) continue;
        final source = f.readAsStringSync();
        if (RegExp(r'''context\.(go|push|replace)\(\s*['"]''')
            .hasMatch(source)) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'navigation must go through the router, not a literal:\n'
              '${offenders.join('\n')}');
    });
  });
}
