import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/pos/data/pos_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/pos/presentation/controllers/pos_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/pos/presentation/screens/pos_screen.dart';

import 'fakes.dart';

void main() {
  group('PosController', () {
    ProviderContainer makeContainer(
      FakePosRepo repo, {
      int? shopId = 10,
    }) {
      final container = ProviderContainer(overrides: [
        posRepositoryProvider.overrideWithValue(repo),
        tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token')),
        selectedShopProvider.overrideWith(() =>
            SelectedShopOverride(shopId == null ? null : ownerShop(id: shopId))),
      ]);
      addTearDown(container.dispose);
      return container;
    }

    test('loads the connected integration with its real sync history',
        () async {
      final repo = FakePosRepo(
        integrations: [posIntegration()],
        jobs: [posJob(itemsSucceeded: 5)],
      );
      final container = makeContainer(repo);

      await container.read(posControllerProvider.notifier).load();

      final state = container.read(posControllerProvider);
      expect(state.status, PosStatus.ready);
      expect(state.needsOnboarding, isFalse);
      expect(state.integration?.isConnected, isTrue);
      expect(state.jobs, hasLength(1));
      expect(state.jobs.first.itemsSucceeded, 5);
      expect(repo.statusCalls, 1);
      expect(repo.jobsCalls, 1);
    });

    test('no integration yet → onboarding state with the provider catalogue',
        () async {
      final repo = FakePosRepo();
      final container = makeContainer(repo);

      await container.read(posControllerProvider.notifier).load();

      final state = container.read(posControllerProvider);
      expect(state.status, PosStatus.ready);
      expect(state.needsOnboarding, isTrue);
      expect(state.providers, hasLength(1));
      expect(state.providers.first.code, 'MOCK');
      expect(repo.providerCalls, 1);
    });

    test('403 surfaces the POS permission copy', () async {
      final repo = FakePosRepo(
        listError: const ApiException(statusCode: 403, message: 'Denied'),
      );
      final container = makeContainer(repo);

      await container.read(posControllerProvider.notifier).load();

      final state = container.read(posControllerProvider);
      expect(state.status, PosStatus.error);
      expect(state.message, contains('permission to manage POS'));
    });

    test('offline failure lands in error (never a fake status)', () async {
      final repo = FakePosRepo(
        listError: const ApiException(message: 'SocketException'),
      );
      final container = makeContainer(repo);

      await container.read(posControllerProvider.notifier).load();

      final state = container.read(posControllerProvider);
      expect(state.status, PosStatus.error);
      expect(state.message, contains('No internet'));
    });

    test('no selected shop → noShop without any network call', () async {
      final repo = FakePosRepo();
      final container = makeContainer(repo, shopId: null);

      await container.read(posControllerProvider.notifier).load();

      final state = container.read(posControllerProvider);
      expect(state.status, PosStatus.noShop);
      expect(repo.listCalls, 0);
    });

    test('connect registers the provider, validates, and reloads ACTIVE',
        () async {
      final repo = FakePosRepo();
      final container = makeContainer(repo);

      final ok = await container
          .read(posControllerProvider.notifier)
          .connect('MOCK');

      expect(ok, isTrue);
      final state = container.read(posControllerProvider);
      expect(state.status, PosStatus.ready);
      expect(state.needsOnboarding, isFalse);
      expect(state.integration?.status, 'ACTIVE');
      expect(repo.registerCalls, 1);
      expect(repo.connectCalls, 1);
      expect(repo.lastRegisteredProvider, 'MOCK');
    });

    test('credential refusal reports false and keeps the PENDING connector',
        () async {
      final repo = FakePosRepo(connectResult: false);
      final container = makeContainer(repo);

      final ok = await container
          .read(posControllerProvider.notifier)
          .connect('MOCK');

      expect(ok, isFalse);
      final state = container.read(posControllerProvider);
      expect(state.status, PosStatus.ready);
      expect(state.integration?.status, 'PENDING');
    });

    test('syncNow queues a job and refreshes status + history', () async {
      final repo = FakePosRepo(
        integrations: [posIntegration()],
        jobs: [posJob(status: 'QUEUED', itemsSucceeded: 0)],
        syncJobResult: posJob(status: 'QUEUED', itemsSucceeded: 0),
      );
      final container = makeContainer(repo);
      await container.read(posControllerProvider.notifier).load();
      final statusCallsBefore = repo.statusCalls;

      final job = await container.read(posControllerProvider.notifier).syncNow();

      expect(job?.status, 'QUEUED');
      expect(repo.syncCalls, 1);
      // Status + history were refreshed after the trigger.
      expect(repo.statusCalls, greaterThan(statusCallsBefore));
      final state = container.read(posControllerProvider);
      expect(state.jobs.first.isQueued, isTrue);
    });

    test('syncNow failure carries the friendly copy', () async {
      final repo = FakePosRepo(
        integrations: [posIntegration()],
        syncError: const ApiException(statusCode: 409, message: 'Busy'),
      );
      final container = makeContainer(repo);
      await container.read(posControllerProvider.notifier).load();

      final job = await container.read(posControllerProvider.notifier).syncNow();

      expect(job, isNull);
      final state = container.read(posControllerProvider);
      expect(state.status, PosStatus.error);
      expect(state.message, 'Busy');
    });

    test('disconnect flips the connector to DISCONNECTED', () async {
      final repo = FakePosRepo(integrations: [posIntegration()]);
      final container = makeContainer(repo);
      await container.read(posControllerProvider.notifier).load();

      await container.read(posControllerProvider.notifier).disconnect();

      final state = container.read(posControllerProvider);
      expect(state.integration?.isDisconnected, isTrue);
      expect(repo.disconnectCalls, 1);
    });
  });

  group('PosScreen (widget)', () {
    Widget wrap(FakePosRepo repo, {int? shopId = 10}) => ProviderScope(
          overrides: [
            posRepositoryProvider.overrideWithValue(repo),
            tokenStoreProvider.overrideWithValue(
                InMemoryTokenStore(accessToken: 'test-access-token')),
            selectedShopProvider.overrideWith(() => SelectedShopOverride(
                shopId == null ? null : ownerShop(id: shopId))),
          ],
          child: const MaterialApp(home: PosScreen()),
        );

    testWidgets('first run shows the connect flow with real providers',
        (tester) async {
      final repo = FakePosRepo();
      await tester.pumpWidget(wrap(repo));
      await tester.pumpAndSettle();

      expect(find.text('Connect your billing counter'), findsOneWidget);
      expect(find.text('Mock POS (built-in)'), findsOneWidget);
      expect(find.text('Connect POS'), findsOneWidget);
    });

    testWidgets('connected view shows provider, actions and real history',
        (tester) async {
      final repo = FakePosRepo(
        integrations: [posIntegration()],
        jobs: [posJob(itemsSucceeded: 5)],
      );
      await tester.pumpWidget(wrap(repo));
      await tester.pumpAndSettle();

      expect(find.text('Mock POS (built-in)'), findsOneWidget);
      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('Sync now'), findsOneWidget);
      expect(find.text('Disconnect'), findsOneWidget);
      expect(find.text('5 products synced'), findsOneWidget);
      expect(find.text('Full sync'), findsOneWidget);
    });

    testWidgets('failed sync surfaces the backend error summary',
        (tester) async {
      final repo = FakePosRepo(
        integrations: [posIntegration()],
        jobs: [
          posJob(
            status: 'FAILED',
            itemsSucceeded: 0,
            errorSummary: 'Provider timeout',
          ),
        ],
      );
      await tester.pumpWidget(wrap(repo));
      await tester.pumpAndSettle();

      expect(find.text('Provider timeout'), findsOneWidget);
    });

    testWidgets('backend error shows the message with Retry', (tester) async {
      final repo = FakePosRepo(
        listError:
            const ApiException(statusCode: 500, message: 'Server exploded'),
      );
      await tester.pumpWidget(wrap(repo));
      await tester.pumpAndSettle();

      expect(find.text('Server exploded'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('no selected shop renders the no-shop state', (tester) async {
      final repo = FakePosRepo();
      await tester.pumpWidget(wrap(repo, shopId: null));
      await tester.pumpAndSettle();

      expect(find.text('No shop selected'), findsOneWidget);
    });

    testWidgets('empty provider catalogue reads as not configured',
        (tester) async {
      // No providers registered for this deployment → the spec's exact copy,
      // never a generic "nothing available" or a fake connect form.
      final repo = FakePosRepo(providers: []);
      await tester.pumpWidget(wrap(repo));
      await tester.pumpAndSettle();

      expect(
        find.text('POS integration is not configured for your account.'),
        findsOneWidget,
      );
      expect(find.text('Connect POS'), findsNothing);
    });

    testWidgets('a queued job renders the Syncing status, not Connected',
        (tester) async {
      final repo = FakePosRepo(
        integrations: [
          posIntegration(
            latestJob: posJob(status: 'QUEUED', itemsSucceeded: 0),
          ),
        ],
        jobs: [posJob(status: 'QUEUED', itemsSucceeded: 0)],
      );
      await tester.pumpWidget(wrap(repo));
      await tester.pumpAndSettle();

      expect(find.text('Syncing'), findsOneWidget);
      expect(find.text('Connected'), findsNothing);
    });

    testWidgets('an errored connector never reads as Syncing', (tester) async {
      final repo = FakePosRepo(
        integrations: [
          posIntegration(
            status: 'ERROR',
            latestJob: posJob(status: 'RUNNING', itemsSucceeded: 0),
          ),
        ],
      );
      await tester.pumpWidget(wrap(repo));
      await tester.pumpAndSettle();

      expect(find.text('Error'), findsOneWidget);
      expect(find.text('Syncing'), findsNothing);
    });

    testWidgets('a disconnected connector reads Not Connected', (tester) async {
      final repo = FakePosRepo(
        integrations: [posIntegration(status: 'DISCONNECTED')],
      );
      await tester.pumpWidget(wrap(repo));
      await tester.pumpAndSettle();

      expect(find.text('Not Connected'), findsOneWidget);
      expect(find.text('Connected'), findsNothing);
    });
  });
}
