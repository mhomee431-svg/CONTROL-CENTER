import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/core/state/system_state.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/data/inventory_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/data/product_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/presentation/controllers/products_controller.dart';

import 'fakes.dart';

/// Spec §136 NETWORK TESTING — behaviour under: fast internet, slow internet,
/// offline, reconnect, server 500, server 401, server 403, server 404, server
/// 409, server 422, server timeout.
///
/// The CLASSIFICATION of every status is already pinned by `system_state_test`
/// (`SystemStateSpec.classify`) and its copy by the same suite, so this file does
/// not re-assert the mapping in isolation. It tests the layer that was missing:
/// what a real SCREEN-LEVEL read does with each answer, and what latency does.
///
/// The behaviours that matter most, and that a status-code table cannot prove:
///   * a SLOW but successful response stays `loading` — it is never mistaken for
///     an error, and a stale "we failed" banner never appears over live work;
///   * a transport failure never leaks Dio-speak into the message a shopkeeper
///     reads ("The connection errored at [GET] …" is not copy);
///   * a 403 is the ONLY status that changes the state ENUM rather than just the
///     message, because "you may not see this shop" is not retryable;
///   * no failure ever fabricates data — an empty list and a failed load must
///     never look alike.
void main() {
  ShopProductItem row({int id = 1, String name = 'Amul Milk'}) => ShopProductItem(
        id: id,
        name: name,
        status: 'ACTIVE',
        price: 30,
        isActive: true,
        isAvailable: true,
        quantity: 12,
        stockStatus: 'IN_STOCK',
      );

  ProviderContainer makeContainer(FakeProductRepo repo) {
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

  /// A read that fails with exactly [error].
  Future<ProductsState> loadFailingWith(ApiException error) async {
    final repo = FakeProductRepo(items: [row()])..overviewError = error;
    final container = makeContainer(repo);
    await container.read(productsControllerProvider.notifier).load();
    return container.read(productsControllerProvider);
  }

  // ── §136: fast internet ───────────────────────────────────────────────────
  group('fast internet', () {
    test('a prompt response lands as data, with no error and no spinner', () async {
      final container = makeContainer(FakeProductRepo(items: [row()]));

      await container.read(productsControllerProvider.notifier).load();

      final state = container.read(productsControllerProvider);
      expect(state.status, ProductsStatus.ready);
      expect(state.items, hasLength(1));
      expect(state.message, isNull);
    });
  });

  // ── §136: slow internet ───────────────────────────────────────────────────
  group('slow internet', () {
    test('a slow-but-successful response stays LOADING, never becomes an error',
        () async {
      // THE point of the slow case. A response that is merely late is still a
      // success; showing an error (or worse, an empty list) while the request is
      // in flight tells the shopkeeper their inventory is gone.
      final gate = Completer<void>();
      final repo = FakeProductRepo(items: [row()])..overviewGate = gate;
      final container = makeContainer(repo);

      final pending =
          container.read(productsControllerProvider.notifier).load();

      // Well past any plausible "it must have failed by now" instinct, but
      // still inside the client's own timeout budget.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      var state = container.read(productsControllerProvider);
      expect(state.status, ProductsStatus.loading);
      expect(state.message, isNull, reason: 'no failure copy while still working');

      gate.complete();
      await pending;

      state = container.read(productsControllerProvider);
      expect(state.status, ProductsStatus.ready);
      expect(state.items, hasLength(1));
    });

    test('a silent pull-to-refresh keeps the OLD rows on screen while loading',
        () async {
      // The silent refresh contract: a slow network must never blank a list the
      // shopkeeper is already reading.
      final repo = FakeProductRepo(items: [row()]);
      final container = makeContainer(repo);
      final controller = container.read(productsControllerProvider.notifier);

      await controller.load();
      expect(container.read(productsControllerProvider).items, hasLength(1));

      // Hold ONLY the refresh open, with a fresh gate — the first load's would
      // already be complete, so re-using it would not block anything.
      final gate = Completer<void>();
      repo.overviewGate = gate;
      final pending = controller.refresh();

      await Future<void>.delayed(const Duration(milliseconds: 50));
      // Still the rows from before — not a spinner, not an empty page.
      expect(container.read(productsControllerProvider).items, hasLength(1));

      gate.complete();
      await pending;
      expect(container.read(productsControllerProvider).items, hasLength(1));
    });
  });

  // ── §136: offline + reconnect ─────────────────────────────────────────────
  group('offline and reconnect', () {
    test('offline explains itself and never invents data', () async {
      // Built the way production builds it, so the app's own offline copy is
      // what lands in the message.
      final repo = FakeProductRepo(items: [row()])
        ..overviewError = ApiException.fromDioError(
          DioException(
            requestOptions:
                RequestOptions(path: '/api/v1/shopkeeper/shops/10/inventory'),
            type: DioExceptionType.connectionError,
            message: 'DioException [connection error]: The connection errored '
                'at [GET] /api/v1/shopkeeper/shops/10/inventory',
          ),
        );
      final container = makeContainer(repo);
      await container.read(productsControllerProvider.notifier).load();

      final state = container.read(productsControllerProvider);
      expect(state.status, ProductsStatus.error);
      // No Dio-speak, and definitely not a fake empty catalog.
      expect(state.message, isNot(contains('DioException')));
      expect(state.message, isNot(contains('connection errored')));
      expect(state.message, isNot(contains('/api/v1')));
      expect(state.items, isEmpty);
    });

    test('the same read succeeding again clears the failure', () async {
      // RECONNECT: the error is transient state, not a poisoned controller.
      final repo = FakeProductRepo(items: [row()])
        ..overviewError = const ApiException(statusCode: null, message: 'x');
      final container = makeContainer(repo);
      final controller = container.read(productsControllerProvider.notifier);

      await controller.load();
      expect(container.read(productsControllerProvider).status,
          ProductsStatus.error);

      repo.overviewError = null;
      await controller.load();

      final state = container.read(productsControllerProvider);
      expect(state.status, ProductsStatus.ready);
      expect(state.items, hasLength(1));
      // The stale failure copy must not linger over fresh data.
      expect(state.message, isNull);
    });
  });

  // ── §136: every server answer reaches its OWN state ───────────────────────
  group('server responses each get their own treatment', () {
    test('server 500 is a server error carrying the backend wording', () async {
      final state = await loadFailingWith(
        const ApiException(
          statusCode: 500,
          errorCode: 'INTERNAL_ERROR',
          message: 'Unexpected error while processing your request',
        ),
      );

      expect(state.status, ProductsStatus.error);
      // The server explained itself, so its own sentence is used — not a
      // generic "something went wrong" that hides what actually broke.
      expect(state.message, contains('Unexpected error'));
      expect(SystemStateSpec.classify(statusCode: 500), SystemState.serverError);
    });

    test('server 401 replaces Dio-speak with "session expired" copy', () async {
      // The worst case for leaking internals. This builds the exception the way
      // production does — through `fromDioError`, where the sanitisation
      // actually happens — rather than hand-constructing one, because a
      // hand-built ApiException keeps whatever message it was given and would
      // make this test pass (or fail) for the wrong reason.
      final repo = FakeProductRepo(items: [row()])
        ..overviewError = ApiException.fromDioError(
          DioException(
            requestOptions: RequestOptions(path: '/api/v1/shopkeeper/shops/10/inventory'),
            type: DioExceptionType.badResponse,
            message: 'The connection errored at [GET] /api/v1/…: 401',
            response: Response<dynamic>(
              requestOptions: RequestOptions(path: '/api/v1/shopkeeper/shops/10/inventory'),
              statusCode: 401,
              data: <String, dynamic>{
                'success': false,
                'message': 'Token expired',
                'error_code': 'TOKEN_EXPIRED',
              },
            ),
          ),
        );
      final container = makeContainer(repo);
      await container.read(productsControllerProvider.notifier).load();

      final state = container.read(productsControllerProvider);
      expect(state.status, ProductsStatus.error);
      // Neither the transport sentence nor Dio's request line may reach the UI.
      expect(state.message, isNot(contains('connection errored')));
      expect(state.message, isNot(contains('/api/v1')));
      expect(state.message, isNotEmpty);
    });

    test('server 403 is the ONE status that changes the state enum', () async {
      // "You may not see this shop" is not a retryable failure — it gets its own
      // state so the screen offers "switch shop" rather than "Retry".
      final state = await loadFailingWith(
        const ApiException(statusCode: 403, message: 'You do not own this shop'),
      );

      expect(state.status, ProductsStatus.accessDenied);
      expect(
        SystemStateSpec.classify(statusCode: 403),
        SystemState.permissionDenied,
      );
    });

    test('server 404 says the thing is gone, not that the app broke', () async {
      final state = await loadFailingWith(
        const ApiException(statusCode: 404, message: 'Shop not found'),
      );

      expect(state.status, ProductsStatus.error);
      expect(state.message, 'Shop not found');
      expect(SystemStateSpec.classify(statusCode: 404), SystemState.notFound);
    });

    test('server 409 is a conflict — refresh before retrying', () async {
      final state = await loadFailingWith(
        const ApiException(
          statusCode: 409,
          message: 'Inventory was modified by another device',
        ),
      );

      expect(state.status, ProductsStatus.error);
      expect(state.message, contains('another device'));
      expect(SystemStateSpec.classify(statusCode: 409), SystemState.conflict);
    });

    test('server 422 is a validation problem with the field detail', () async {
      final state = await loadFailingWith(
        const ApiException(
          statusCode: 422,
          errorCode: 'VALIDATION_ERROR',
          message: 'price: must be greater than or equal to 0',
        ),
      );

      expect(state.status, ProductsStatus.error);
      // The shopkeeper needs WHICH field to fix, so the detail must survive.
      expect(state.message, contains('price'));
      expect(SystemStateSpec.classify(statusCode: 422), SystemState.validation);
    });

    test('a server timeout is a TIMEOUT, not "you are offline"', () async {
      // The distinction a shopkeeper acts on: offline means "turn on Wi-Fi";
      // a timeout means "the server is slow — try again". Collapsing them sends
      // people to the wrong settings screen. Built through `fromDioError` so the
      // real sanitisation path runs.
      final repo = FakeProductRepo(items: [row()])
        ..overviewError = ApiException.fromDioError(
          DioException(
            requestOptions:
                RequestOptions(path: '/api/v1/shopkeeper/shops/10/inventory'),
            type: DioExceptionType.receiveTimeout,
            message: 'DioException [receive timeout]: 0:00:30',
          ),
        );
      final container = makeContainer(repo);
      await container.read(productsControllerProvider.notifier).load();

      final state = container.read(productsControllerProvider);
      expect(state.status, ProductsStatus.error);
      expect(state.message, isNot(contains('DioException')));
      expect(state.message, isNot(contains('receive timeout')));
      expect(
        SystemStateSpec.classify(failureKind: ApiFailureKind.timeout),
        SystemState.timeout,
      );
      // …and it is NOT the offline state.
      expect(
        SystemStateSpec.classify(failureKind: ApiFailureKind.timeout),
        isNot(SystemState.offline),
      );
    });

    test('no server answer ever leaves a fabricated empty catalog on screen',
        () async {
      // The shared invariant across ALL eleven conditions: an empty list and a
      // failed load must never look the same, or the shopkeeper reads "you have
      // no products" as truth.
      for (final failure in <ApiException>[
        const ApiException(statusCode: 500, message: 'boom'),
        const ApiException(statusCode: 401, message: 'nope'),
        const ApiException(statusCode: 403, message: 'nope'),
        const ApiException(statusCode: 404, message: 'nope'),
        const ApiException(statusCode: 409, message: 'nope'),
        const ApiException(statusCode: 422, message: 'nope'),
        const ApiException(statusCode: null, message: 'nope'),
      ]) {
        final state = await loadFailingWith(failure);
        expect(
          state.status,
          isNot(ProductsStatus.ready),
          reason: 'a $failure must not read as a successful empty catalog',
        );
        expect(state.items, isEmpty);
      }
    });
  });
}