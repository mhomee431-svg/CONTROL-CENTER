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
import 'package:hyperlocal_shopkeeper_app/features/offers/presentation/widgets/offer_create_sheet.dart';
import 'package:hyperlocal_shopkeeper_app/features/offers/presentation/widgets/offer_details_sheet.dart';

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

    testWidgets('lists deactivated offers on the Disabled tab, not Active',
        (tester) async {
      final repo = FakeOffersRepo(
        page: OfferListPage(items: [
          offerSummary(id: 1, status: 'ACTIVE', title: 'Live deal'),
          offerSummary(id: 2, status: 'DISABLED', title: 'Paused deal'),
        ], count: 2),
      );
      await tester.pumpWidget(wrap(repo));
      await tester.pumpAndSettle();

      // A disabled offer is NOT live stock — it must stay off the Active tab.
      expect(find.text('Live deal'), findsOneWidget);
      expect(find.text('Paused deal'), findsNothing);

      await tester.tap(find.text('Disabled'));
      await tester.pumpAndSettle();

      expect(find.text('Paused deal'), findsOneWidget);
      // Tab label + the row's own status label — never 'Expired'.
      expect(find.text('Disabled'), findsNWidgets(2));

      // The Expired tab is untouched by a disabled offer.
      await tester.tap(find.text('Expired'));
      await tester.pumpAndSettle();
      expect(find.text('No expired offers'), findsOneWidget);
      expect(find.text('Paused deal'), findsNothing);
    });

    testWidgets('empty Disabled tab explains offers can be re-activated',
        (tester) async {
      final repo = FakeOffersRepo();
      await tester.pumpWidget(wrap(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Disabled'));
      await tester.pumpAndSettle();

      expect(find.text('No disabled offers'), findsOneWidget);
    });

    testWidgets('the Scheduled chip shows scheduled offers only',
        (tester) async {
      final repo = FakeOffersRepo(
        page: OfferListPage(
          items: [
            offerSummary(id: 1, status: 'ACTIVE', title: 'Live deal'),
            offerSummary(id: 2, status: 'SCHEDULED', title: 'Diwali deal'),
          ],
          count: 2,
        ),
      );
      await tester.pumpWidget(wrap(repo));
      await tester.pumpAndSettle();

      // Active must NOT contain the future-window offer…
      expect(find.text('Live deal'), findsOneWidget);
      expect(find.text('Diwali deal'), findsNothing);

      await tester.tap(find.text('Scheduled'));
      await tester.pumpAndSettle();

      expect(find.text('Diwali deal'), findsOneWidget);
      expect(find.text('Live deal'), findsNothing);
      // Chip label + the row's own status label.
      expect(find.text('Scheduled'), findsNWidgets(2));
    });
  });

  group('OfferSummary lifecycle rules', () {
    test('mirrors the backend transition table', () {
      expect(offerSummary(status: 'DRAFT').canActivate, isTrue);
      expect(offerSummary(status: 'DRAFT').canDisable, isTrue);
      expect(offerSummary(status: 'ACTIVE').canDisable, isTrue);
      expect(offerSummary(status: 'ACTIVE').canActivate, isFalse);
      expect(offerSummary(status: 'DISABLED').canActivate, isTrue);
      expect(offerSummary(status: 'DISABLED').canDisable, isFalse);
      expect(offerSummary(status: 'PAUSED').canActivate, isTrue);
    });

    test('expired and cancelled offers are terminal', () {
      expect(offerSummary(status: 'EXPIRED').canTransitionTo('ACTIVE'), isFalse);
      expect(offerSummary(status: 'EXPIRED').canDisable, isFalse);
      expect(offerSummary(status: 'CANCELLED').canActivate, isFalse);
    });

    test('reads the STORED status, not the derived display bucket', () {
      // A live offer whose window has already closed: the bucket says EXPIRED
      // but the backend still stores ACTIVE, so disabling remains legal.
      final offer = offerSummary(status: 'ACTIVE', displayStatus: 'EXPIRED');
      expect(offer.isExpired, isTrue);
      expect(offer.canDisable, isTrue);
    });

    test('promotional price renders as a promo label', () {
      final offer = offerSummary(
        offerType: 'PROMOTIONAL_PRICE',
        discountPercentage: null,
        promotionalPrice: 199,
      );
      expect(offer.discountLabel, 'Promo ₹199');
      expect(offer.offerTypeLabel, 'Promo price');
    });
  });

  group('OfferValidators promotional price', () {
    test('promo price is required and must be positive', () {
      expect(
        OfferValidators.discount(
            ShopkeeperOfferType.promotionalPrice, '', '', ''),
        'Promotional price is required',
      );
      expect(
        OfferValidators.discount(
            ShopkeeperOfferType.promotionalPrice, '', '', '0'),
        'Promotional price is required',
      );
      expect(
        OfferValidators.discount(
            ShopkeeperOfferType.promotionalPrice, '', '', '199'),
        isNull,
      );
    });

    test('only the promo price is sent for a promotional offer', () {
      final json = OfferAssignRequest(
        title: 'Festive promo',
        offerType: ShopkeeperOfferType.promotionalPrice,
        promotionalPrice: 199,
        startDate: DateTime(2026, 1, 12),
        endDate: DateTime(2026, 1, 20),
        shopProductIds: const [1],
      ).toJson();

      expect(json['offer_type'], 'PROMOTIONAL_PRICE');
      expect(json['promotional_price'], 199);
      expect(json.containsKey('discount_percentage'), isFalse);
      expect(json.containsKey('discount_value'), isFalse);
    });
  });

  group('OfferDetailsSheet actions (widget)', () {
    ProviderContainer makeContainer(FakeOffersRepo repo) {
      final container = ProviderContainer(overrides: [
        offersRepositoryProvider.overrideWithValue(repo),
        tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token')),
        selectedShopProvider
            .overrideWith(() => SelectedShopOverride(ownerShop(id: 10))),
      ]);
      addTearDown(container.dispose);
      return container;
    }

    Future<void> openSheet(
      WidgetTester tester,
      ProviderContainer container,
      OfferSummary offer,
    ) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showOfferDetailsSheet(context, offer),
                  child: const Text('open sheet'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open sheet'));
      await tester.pumpAndSettle();
    }

    testWidgets('a live offer can only be disabled', (tester) async {
      final repo = FakeOffersRepo(
        page: OfferListPage(
            items: [offerSummary(id: 7, status: 'ACTIVE')], count: 1),
      );
      final container = makeContainer(repo);
      await openSheet(tester, container, offerSummary(id: 7, status: 'ACTIVE'));

      expect(find.text('Disable offer'), findsOneWidget);
      expect(find.text('Activate offer'), findsNothing);

      await tester.tap(find.text('Disable offer'));
      await tester.pumpAndSettle();

      // §74: disabling asks first, and asking alone writes nothing.
      expect(find.text('Disable this offer?'), findsOneWidget);
      expect(repo.requestedTransitions, isEmpty);

      await tester.tap(find.byKey(const Key('confirm_disable_offer')));
      await tester.pumpAndSettle();

      expect(repo.requestedTransitions, ['DISABLED']);
      // Sheet closes and the list is refreshed so the tab is up to date.
      expect(find.text('Disable offer'), findsNothing);
      expect(repo.fetchCalls, greaterThan(0));
      expect(find.text('Offer disabled'), findsOneWidget);
    });

    testWidgets('cancelling the disable confirmation writes nothing',
        (tester) async {
      final repo = FakeOffersRepo(
        page: OfferListPage(
            items: [offerSummary(id: 7, status: 'ACTIVE')], count: 1),
      );
      final container = makeContainer(repo);
      await openSheet(tester, container, offerSummary(id: 7, status: 'ACTIVE'));

      await tester.tap(find.text('Disable offer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // The live discount was never pulled — and the sheet is still there.
      expect(repo.requestedTransitions, isEmpty);
      expect(find.text('Disable this offer?'), findsNothing);
      expect(find.text('Disable offer'), findsOneWidget);
    });

    testWidgets('the confirmation names the offer and explains the impact',
        (tester) async {
      final repo = FakeOffersRepo(
        page: OfferListPage(
            items: [offerSummary(id: 7, status: 'ACTIVE')], count: 1),
      );
      final container = makeContainer(repo);
      await openSheet(tester, container, offerSummary(id: 7, status: 'ACTIVE'));

      await tester.tap(find.text('Disable offer'));
      await tester.pumpAndSettle();

      // §74 "explain impact clearly": which offer, and what survives. The
      // title appears twice — on the sheet behind and in the dialog's own
      // sentence, which is the point.
      expect(find.textContaining('will stop being shown to customers'),
          findsOneWidget);
      expect(find.textContaining('not deleted'), findsOneWidget);
    });

    testWidgets('a disabled offer can be re-activated', (tester) async {
      final repo = FakeOffersRepo(
        page: OfferListPage(
            items: [offerSummary(id: 8, status: 'DISABLED')], count: 1),
      );
      final container = makeContainer(repo);
      await openSheet(
          tester, container, offerSummary(id: 8, status: 'DISABLED'));

      expect(find.text('Activate offer'), findsOneWidget);
      expect(find.text('Disable offer'), findsNothing);
      // Labelled Disabled, never mistaken for Expired.
      expect(find.text('Disabled'), findsWidgets);
      expect(find.text('Expired'), findsNothing);

      await tester.tap(find.text('Activate offer'));
      await tester.pumpAndSettle();

      expect(repo.requestedTransitions, ['ACTIVE']);
    });

    testWidgets('an expired offer shows a terminal note, not dead buttons',
        (tester) async {
      final repo = FakeOffersRepo();
      final container = makeContainer(repo);
      await openSheet(
          tester, container, offerSummary(id: 9, status: 'EXPIRED'));

      expect(find.text('Activate offer'), findsNothing);
      expect(find.text('Disable offer'), findsNothing);
      expect(find.textContaining('has ended'), findsOneWidget);
      expect(repo.statusCalls, 0);
    });

    testWidgets('a rejected transition stays open and shows the server message',
        (tester) async {
      final repo = FakeOffersRepo(
        statusError: const ApiException(
          statusCode: 400,
          message: 'Cannot move an offer from EXPIRED to ACTIVE',
        ),
      );
      final container = makeContainer(repo);
      await openSheet(tester, container, offerSummary(id: 7, status: 'ACTIVE'));

      await tester.tap(find.text('Disable offer'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_disable_offer')));
      await tester.pumpAndSettle();

      expect(repo.requestedTransitions, ['DISABLED']);
      // Still open for a retry, showing the backend's own wording.
      expect(find.text('Disable offer'), findsOneWidget);
      expect(find.textContaining('Cannot move an offer'), findsOneWidget);
    });
  });

  group('OfferCreateSheet promotional price (widget)', () {
    testWidgets('shows the promo price input ONLY for a promo offer',
        (tester) async {
      final container = ProviderContainer(overrides: [
        offersRepositoryProvider.overrideWithValue(FakeOffersRepo()),
        tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token')),
        selectedShopProvider
            .overrideWith(() => SelectedShopOverride(ownerShop(id: 10))),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: OfferCreateSheet())),
        ),
      );
      await tester.pumpAndSettle();

      // The default type is a percentage offer.
      expect(find.text('Promotional price *'), findsNothing);

      await tester
          .tap(find.byType(DropdownButtonFormField<ShopkeeperOfferType>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Promo price').last);
      await tester.pumpAndSettle();

      expect(find.text('Promotional price *'), findsOneWidget);
      expect(find.text('Discount % *'), findsNothing);
    });

    testWidgets('offers a Save-as-draft switch, off by default', (tester) async {
      final container = ProviderContainer(overrides: [
        offersRepositoryProvider.overrideWithValue(FakeOffersRepo()),
        tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token')),
        selectedShopProvider
            .overrideWith(() => SelectedShopOverride(ownerShop(id: 10))),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: OfferCreateSheet())),
        ),
      );
      await tester.pumpAndSettle();

      final toggle = find.byKey(const Key('offer-save-as-draft'));
      expect(toggle, findsOneWidget);
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    });
  });

  group('OfferAssignRequest draft status', () {
    OfferAssignRequest request(String? status) => OfferAssignRequest(
          title: 'Winter sale',
          offerType: ShopkeeperOfferType.percentageDiscount,
          discountPercentage: 10,
          status: status,
          startDate: DateTime(2026, 1, 12),
          endDate: DateTime(2026, 1, 20),
          shopProductIds: const [1],
        );

    test('omits status so the backend publishes immediately', () {
      expect(request(null).toJson().containsKey('status'), isFalse);
    });

    test('sends DRAFT when the shopkeeper parks the offer', () {
      expect(request('DRAFT').toJson()['status'], 'DRAFT');
    });
  });
}

