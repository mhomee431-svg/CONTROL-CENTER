import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/offers/data/offers_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/offers/domain/offer_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/offers/presentation/controllers/offers_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/offers/presentation/screens/offers_screen.dart';

import 'fakes.dart';

OfferAssignRequest _assignRequest() => OfferAssignRequest(
      title: 'Monsoon Sale',
      offerType: ShopkeeperOfferType.percentageDiscount,
      discountPercentage: 15,
      startDate: DateTime(2026, 1, 12),
      endDate: DateTime(2026, 1, 20),
      shopProductIds: const [1, 2],
    );

void main() {
  group('OffersListController', () {
    ProviderContainer makeContainer(
      FakeOffersRepo repo, {
      int? shopId = 10,
    }) {
      final container = ProviderContainer(overrides: [
        offersRepositoryProvider.overrideWithValue(repo),
        tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token')),
        selectedShopProvider.overrideWith(() =>
            SelectedShopOverride(shopId == null ? null : ownerShop(id: shopId))),
      ]);
      addTearDown(container.dispose);
      return container;
    }

    test('loads offers for the selected shop', () async {
      final page = OfferListPage(
        items: [offerSummary()],
        count: 1,
      );
      final fake = FakeOffersRepo(page: page);
      final container = makeContainer(fake);

      await container.read(offersListControllerProvider.notifier).load();

      final state = container.read(offersListControllerProvider);
      expect(state.status, OffersListStatus.ready);
      expect(state.items, hasLength(1));
      expect(state.items.first.title, 'Monsoon Sale');
      expect(fake.fetchCalls, 1);
      // The list fetch is UNFILTERED — both tabs are sliced client-side.
      expect(fake.requestedStatuses.single, isNull);
    });

    test('slices the same fetch into open and expired tabs', () async {
      final page = OfferListPage(
        items: [
          offerSummary(id: 1, status: 'ACTIVE'),
          offerSummary(id: 2, status: 'DRAFT', title: 'Draft deal'),
          offerSummary(id: 3, status: 'EXPIRED', title: 'Old deal'),
        ],
        count: 3,
      );
      final fake = FakeOffersRepo(page: page);
      final container = makeContainer(fake);

      await container.read(offersListControllerProvider.notifier).load();

      final state = container.read(offersListControllerProvider);
      expect(state.openOffers.map((o) => o.id), [1, 2]);
      expect(state.expiredOffers.map((o) => o.id), [3]);
    });

    test('403 surfaces the offers-specific forbidden copy', () async {
      final fake = FakeOffersRepo(
        listError: const ApiException(
            statusCode: 403, message: 'You do not have access to this shop.'),
      );
      final container = makeContainer(fake);

      await container.read(offersListControllerProvider.notifier).load();

      final state = container.read(offersListControllerProvider);
      expect(state.status, OffersListStatus.error);
      expect(state.message, contains('do not have access to offers'));
    });

    test('401 asks for a fresh sign-in', () async {
      final fake = FakeOffersRepo(
        listError: const ApiException(statusCode: 401, message: 'Expired'),
      );
      final container = makeContainer(fake);

      await container.read(offersListControllerProvider.notifier).load();

      final state = container.read(offersListControllerProvider);
      expect(state.status, OffersListStatus.error);
      expect(state.message, contains('session has expired'));
    });

    test('offline failure lands in error (never a fake list)', () async {
      final fake = FakeOffersRepo(
        listError: const ApiException(message: 'SocketException'),
      );
      final container = makeContainer(fake);

      await container.read(offersListControllerProvider.notifier).load();

      final state = container.read(offersListControllerProvider);
      expect(state.status, OffersListStatus.error);
      expect(state.message, contains('No internet'));
    });

    test('no selected shop → noShop (no network call)', () async {
      final fake = FakeOffersRepo();
      final container = makeContainer(fake, shopId: null);

      await container.read(offersListControllerProvider.notifier).load();

      final state = container.read(offersListControllerProvider);
      expect(state.status, OffersListStatus.noShop);
      expect(fake.fetchCalls, 0);
    });
  });

  group('OffersController.assign', () {
    ProviderContainer makeContainer(FakeOffersRepo repo, {int? shopId = 10}) {
      final container = ProviderContainer(overrides: [
        offersRepositoryProvider.overrideWithValue(repo),
        tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token')),
        selectedShopProvider.overrideWith(() =>
            SelectedShopOverride(shopId == null ? null : ownerShop(id: shopId))),
      ]);
      addTearDown(container.dispose);
      return container;
    }

    test('publishes the offer and lands in done', () async {
      final fake = FakeOffersRepo(
        assignResult: const OfferAssignResult(
            offerId: 7, title: 'Monsoon Sale', productCount: 2),
      );
      final container = makeContainer(fake);

      final ok = await container
          .read(offersControllerProvider.notifier)
          .assign(_assignRequest());

      expect(ok, isTrue);
      final state = container.read(offersControllerProvider);
      expect(state.status, OfferAssignStatus.done);
      expect(state.result?.offerId, 7);
      expect(fake.assignCalls, 1);
      // reset() returns the sheet-start state for the next open.
      container.read(offersControllerProvider.notifier).reset();
      expect(
        container.read(offersControllerProvider).status,
        OfferAssignStatus.idle,
      );
    });

    test('403 rejects with the owner-only copy', () async {
      final fake = FakeOffersRepo(
        assignError: const ApiException(statusCode: 403, message: 'Forbidden'),
      );
      final container = makeContainer(fake);

      final ok = await container
          .read(offersControllerProvider.notifier)
          .assign(_assignRequest());

      expect(ok, isFalse);
      final state = container.read(offersControllerProvider);
      expect(state.status, OfferAssignStatus.error);
      expect(state.message, contains('Only shop owners'));
    });

    test('402 (plan limit) shows the backend message', () async {
      final fake = FakeOffersRepo(
        assignError: const ApiException(
          statusCode: 402,
          message: 'Your plan allows 2 active offers.',
        ),
      );
      final container = makeContainer(fake);

      await container
          .read(offersControllerProvider.notifier)
          .assign(_assignRequest());

      final state = container.read(offersControllerProvider);
      expect(state.status, OfferAssignStatus.error);
      expect(state.message, contains('plan allows 2 active offers'));
    });

    test('no shop selected fails fast without calling the API', () async {
      final fake = FakeOffersRepo();
      final container = makeContainer(fake, shopId: null);

      final ok = await container
          .read(offersControllerProvider.notifier)
          .assign(_assignRequest());

      expect(ok, isFalse);
      expect(container.read(offersControllerProvider).message,
          contains('No shop selected'));
      expect(fake.assignCalls, 0);
    });
  });


  group('OffersScreen (widget)', () {
    Widget wrap(FakeOffersRepo repo, {int? shopId = 10}) => ProviderScope(
          overrides: [
            offersRepositoryProvider.overrideWithValue(repo),
            tokenStoreProvider.overrideWithValue(
                InMemoryTokenStore(accessToken: 'test-access-token')),
            selectedShopProvider.overrideWith(() => SelectedShopOverride(
                shopId == null ? null : ownerShop(id: shopId))),
          ],
          child: const MaterialApp(home: OffersScreen()),
        );

    testWidgets('renders live offer rows on the Active tab', (tester) async {
      final repo = FakeOffersRepo(
        page: OfferListPage(items: [
          offerSummary(id: 1, status: 'ACTIVE', title: 'Monsoon Sale'),
        ], count: 1),
      );
      await tester.pumpWidget(wrap(repo));
      await tester.pumpAndSettle();

      expect(find.text('Monsoon Sale'), findsOneWidget);
      expect(find.textContaining('15% off'), findsOneWidget);
      expect(find.text('Live'), findsOneWidget);
      expect(find.text('3 products'), findsOneWidget);
      expect(find.text('No active offers'), findsNothing);
    });

    testWidgets('shows the empty state with a Create offer CTA',
        (tester) async {
      final repo = FakeOffersRepo();
      await tester.pumpWidget(wrap(repo));
      await tester.pumpAndSettle();

      expect(find.text('No active offers'), findsOneWidget);
      expect(find.text('Create offer'), findsOneWidget);
    });

    testWidgets('shows the backend error with a Retry button', (tester) async {
      final repo = FakeOffersRepo(
        listError:
            const ApiException(statusCode: 500, message: 'Server exploded'),
      );
      await tester.pumpWidget(wrap(repo));
      await tester.pumpAndSettle();

      expect(find.text('Server exploded'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('shows the no-shop state when nothing is selected',
        (tester) async {
      final repo = FakeOffersRepo();
      await tester.pumpWidget(wrap(repo, shopId: null));
      await tester.pumpAndSettle();

      expect(find.text('No shop selected'), findsOneWidget);
    });
  });
}

