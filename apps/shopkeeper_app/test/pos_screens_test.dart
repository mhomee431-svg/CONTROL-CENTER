import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/pos/data/pos_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/pos/presentation/controllers/pos_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/pos/presentation/screens/pos_connection_setup_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/pos/presentation/screens/pos_error_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/pos/presentation/screens/pos_sync_history_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/pos/presentation/screens/pos_sync_progress_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/pos/presentation/screens/pos_sync_result_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/pos/presentation/screens/pos_sync_screen.dart';

import 'fakes.dart';

/// POS module screens — Connection Setup, Sync, Sync Progress, Sync Result,
/// Sync History and the diagnostics screen. Only the repository is faked; the
/// controllers and the widgets run for real, and every number on screen comes
/// from the (fake) server payload.

ProviderContainer makeContainer(
  FakePosRepo repo, {
  int? shopId = 10,
  Duration pollInterval = const Duration(minutes: 30),
}) {
  return ProviderContainer(
    overrides: [
      posRepositoryProvider.overrideWithValue(repo),
      tokenStoreProvider.overrideWithValue(
        InMemoryTokenStore(accessToken: 'test-access-token'),
      ),
      selectedShopProvider.overrideWith(
        () =>
            SelectedShopOverride(shopId == null ? null : ownerShop(id: shopId)),
      ),
      // A long cadence keeps the Progress screen's `Timer.periodic` out of the
      // test's virtual time (the screen still owns a real timer).
      posSyncPollIntervalProvider.overrideWithValue(pollInterval),
    ],
  );
}

Future<void> pumpScreen(
  WidgetTester tester,
  ProviderContainer container,
  Widget screen,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('PosConnectionSetupScreen', () {
    testWidgets('first run lists the real providers and connects on submit', (
      tester,
    ) async {
      final repo = FakePosRepo();
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      await pumpScreen(tester, container, const PosConnectionSetupScreen());

      expect(find.byKey(const Key('pos-setup-provider')), findsOneWidget);
      expect(find.byKey(const Key('pos-setup-type')), findsOneWidget);
      expect(find.text('Mock POS (built-in)'), findsWidgets);
      expect(find.text('Connect POS'), findsOneWidget);

      await tester.tap(find.byKey(const Key('pos-setup-submit')));
      await tester.pumpAndSettle();

      expect(repo.registerCalls, 1);
      expect(repo.connectCalls, 1);
      expect(repo.lastRegisteredProvider, 'MOCK');
      expect(find.byKey(const Key('pos-setup-success')), findsOneWidget);
      expect(find.byKey(const Key('pos-setup-status')), findsOneWidget);
    });

    testWidgets('the success panel can start the first sync in place', (
      tester,
    ) async {
      final repo = FakePosRepo();
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      await pumpScreen(tester, container, const PosConnectionSetupScreen());
      await tester.tap(find.byKey(const Key('pos-setup-submit')));
      await tester.pumpAndSettle();

      // Both exits are offered on the live connector...
      expect(find.byKey(const Key('pos-setup-sync-now')), findsOneWidget);
      expect(find.byKey(const Key('pos-setup-done')), findsOneWidget);
      // ...but they must NOT compete: exactly one filled primary, and the
      // secondary demoted to an outline. Two stacked full-width filled buttons
      // read as two primary actions with no obvious winner.
      expect(
        find.byType(FilledButton),
        findsOneWidget,
        reason: 'the connected state must offer exactly ONE primary action',
      );
      expect(
        find.byType(OutlinedButton),
        findsOneWidget,
        reason: 'the second exit is a secondary, so it must be demoted',
      );
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNotNull,
      );
      // ...but connecting alone must not queue a sync.
      expect(repo.syncCalls, 0);

      await tester.tap(find.byKey(const Key('pos-setup-sync-now')));
      await tester.pumpAndSettle();

      expect(repo.syncCalls, 1);
      expect(find.textContaining('Initial sync started'), findsOneWidget);
    });

    testWidgets('a refused sync is reported instead of silently passing', (
      tester,
    ) async {
      final repo = FakePosRepo(
        syncError: const ApiException(message: 'No connection'),
      );
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      await pumpScreen(tester, container, const PosConnectionSetupScreen());
      await tester.tap(find.byKey(const Key('pos-setup-submit')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('pos-setup-sync-now')));
      await tester.pumpAndSettle();

      expect(repo.syncCalls, 1);
      expect(find.textContaining('Sync could not be started'), findsOneWidget);
    });

    testWidgets(
      'credential rotation is sent only when the shopkeeper types it',
      (tester) async {
        final repo = FakePosRepo(
          integrations: [posIntegration(status: 'INACTIVE')],
        );
        final container = makeContainer(repo);
        addTearDown(container.dispose);
        // The hub loads the connector first in the real app.
        await container.read(posControllerProvider.notifier).load();

        await pumpScreen(tester, container, const PosConnectionSetupScreen());

        expect(find.text('Save & reconnect'), findsOneWidget);
        expect(find.textContaining('no duplicate is created'), findsOneWidget);
        // The provider is fixed for an existing connector.
        expect(find.byKey(const Key('pos-setup-provider')), findsNothing);

        await tester.enterText(
          find.byKey(const Key('pos-setup-api-key')),
          'vendor-key',
        );
        await tester.tap(find.byKey(const Key('pos-setup-submit')));
        await tester.pumpAndSettle();

        expect(repo.registerCalls, 0); // never a duplicate connector
        expect(repo.credentialsCalls, 1);
        expect(repo.lastCredentials?.apiKey, 'vendor-key');
        expect(repo.reconnectCalls, 1);
        expect(find.byKey(const Key('pos-setup-success')), findsOneWidget);
      },
    );

    testWidgets('a credential refusal stays on the form with the error card', (
      tester,
    ) async {
      final repo = FakePosRepo(connectResult: false);
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      await pumpScreen(tester, container, const PosConnectionSetupScreen());
      await tester.tap(find.byKey(const Key('pos-setup-submit')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pos-setup-success')), findsNothing);
      expect(find.byKey(const Key('pos-setup-error')), findsOneWidget);
      expect(find.textContaining('check the credentials'), findsOneWidget);
      expect(container.read(posSetupProvider).credentialRefused, isTrue);
    });

    testWidgets('a provider failure offers Retry instead of a dead end', (
      tester,
    ) async {
      final repo = FakePosRepo(
        providersError: const ApiException(message: 'No connection'),
      );
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      await pumpScreen(tester, container, const PosConnectionSetupScreen());

      expect(find.textContaining('No internet connection'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('PosSyncScreen', () {
    testWidgets('shows the connector facts and the scope choice', (
      tester,
    ) async {
      final repo = FakePosRepo(integrations: [posIntegration()]);
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      await pumpScreen(tester, container, const PosSyncScreen());

      expect(find.text('Mock POS (built-in)'), findsWidgets);
      expect(find.byKey(const Key('pos-sync-type-full')), findsOneWidget);
      expect(
        find.byKey(const Key('pos-sync-type-incremental')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('pos-sync-start')), findsOneWidget);

      // The scope uses the server's own vocabulary (FULL / INCREMENTAL).
      await tester.tap(find.byKey(const Key('pos-sync-type-incremental')));
      await tester.pumpAndSettle();

      expect(container.read(posSyncFlowProvider).syncType, 'INCREMENTAL');
    });

    testWidgets('no connector offers ONE primary: the setup action, no bar', (
      tester,
    ) async {
      final repo = FakePosRepo();
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      await pumpScreen(tester, container, const PosSyncScreen());

      expect(find.text('No connector yet'), findsOneWidget);
      expect(find.byKey(const Key('pos-sync-go-setup')), findsOneWidget);

      // DESIGN CONTRACT: with no connector there is nothing to sync, so the
      // bottom bar must NOT render at all. It previously showed a disabled
      // "Start sync" underneath the body's filled "Go to connection setup" --
      // two filled primaries, one of which can never fire. "Primary CTA where
      // necessary" is part of the contract: here the body's action IS the one.
      expect(find.byKey(const Key('pos-sync-start')), findsNothing);
      expect(
        find.byType(FilledButton),
        findsOneWidget,
        reason: 'exactly ONE primary may exist on screen',
      );
    });
  });

  group('PosSyncProgressScreen', () {
    testWidgets('follows a running job with the server counters', (
      tester,
    ) async {
      final running = posJob(
        status: 'RUNNING',
        itemsProcessed: 4,
        itemsSucceeded: 3,
        itemsFailed: 1,
      );
      final repo = FakePosRepo(
        integrations: [posIntegration(latestJob: running)],
        syncJobResult: running,
      );
      final container = makeContainer(repo);
      addTearDown(container.dispose);
      await container.read(posControllerProvider.notifier).load();
      await container.read(posSyncFlowProvider.notifier).start();

      // Deliberately no `pumpAndSettle`: the progress bar animates for as long
      // as the server reports the job as RUNNING.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: PosSyncProgressScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('pos-progress-status')), findsOneWidget);
      expect(find.byKey(const Key('pos-progress-processed')), findsOneWidget);
      expect(find.byKey(const Key('pos-progress-succeeded')), findsOneWidget);
      expect(find.byKey(const Key('pos-progress-failed')), findsOneWidget);
      expect(container.read(posSyncFlowProvider).phase, PosSyncPhase.running);

      // Tear the screen down so its poll timer is cancelled inside the test.
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('PosSyncResultScreen', () {
    testWidgets('a completed job reports the server counters', (tester) async {
      final repo = FakePosRepo(
        integrations: [posIntegration()],
        syncJobResult: posJob(itemsSucceeded: 7, itemsFailed: 1),
      );
      final container = makeContainer(repo);
      addTearDown(container.dispose);
      await container.read(posControllerProvider.notifier).load();
      await container.read(posSyncFlowProvider.notifier).start();

      await pumpScreen(tester, container, const PosSyncResultScreen());

      expect(find.byKey(const Key('pos-sync-result-title')), findsOneWidget);
      expect(find.byKey(const Key('pos-sync-result-detail')), findsOneWidget);
      expect(find.byKey(const Key('pos-result-synced')), findsOneWidget);
      expect(find.byKey(const Key('pos-result-failed')), findsOneWidget);
      expect(
        find.textContaining('7 products synced, 1 failed'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('pos-result-done')), findsOneWidget);
      expect(find.byKey(const Key('pos-result-again')), findsOneWidget);
      expect(find.byKey(const Key('pos-result-history')), findsOneWidget);
    });

    testWidgets('a failed job surfaces the backend error summary', (
      tester,
    ) async {
      final repo = FakePosRepo(
        integrations: [posIntegration()],
        syncJobResult: posJob(
          status: 'FAILED',
          itemsSucceeded: 0,
          errorSummary: 'Provider timeout',
        ),
      );
      final container = makeContainer(repo);
      addTearDown(container.dispose);
      await container.read(posControllerProvider.notifier).load();
      await container.read(posSyncFlowProvider.notifier).start();

      await pumpScreen(tester, container, const PosSyncResultScreen());

      expect(find.text('Provider timeout'), findsOneWidget);
      // A settled job offers another run.
      final again = tester.widget<OutlinedButton>(
        find.byKey(const Key('pos-result-again')),
      );
      expect(again.onPressed, isNotNull);
    });
  });

  group('PosSyncHistoryScreen', () {
    FakePosRepo historyRepo() => FakePosRepo(
      integrations: [posIntegration()],
      jobs: [
        posJob(
          id: 901,
          status: 'FAILED',
          itemsSucceeded: 0,
          errorSummary: 'Provider timeout',
        ),
        posJob(id: 900, itemsSucceeded: 5),
      ],
    );

    testWidgets('lists past jobs and opens the row detail', (tester) async {
      final container = makeContainer(historyRepo());
      addTearDown(container.dispose);
      await container.read(posControllerProvider.notifier).load();

      await pumpScreen(tester, container, const PosSyncHistoryScreen());

      expect(find.byKey(const Key('pos-history-job-901')), findsOneWidget);
      expect(find.byKey(const Key('pos-history-job-900')), findsOneWidget);
      expect(find.text('Provider timeout'), findsOneWidget);
      expect(find.text('5 products synced'), findsOneWidget);

      await tester.tap(find.byKey(const Key('pos-history-job-901')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pos-history-detail')), findsOneWidget);
    });

    testWidgets('the failed filter narrows the list', (tester) async {
      final container = makeContainer(historyRepo());
      addTearDown(container.dispose);
      await container.read(posControllerProvider.notifier).load();

      await pumpScreen(tester, container, const PosSyncHistoryScreen());
      await tester.tap(find.byKey(const Key('pos-history-filter-failed')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pos-history-job-901')), findsOneWidget);
      expect(find.byKey(const Key('pos-history-job-900')), findsNothing);
    });

    testWidgets('no connector points at connection setup', (tester) async {
      final container = makeContainer(FakePosRepo());
      addTearDown(container.dispose);

      await pumpScreen(tester, container, const PosSyncHistoryScreen());

      expect(find.text('No connector yet'), findsOneWidget);
      expect(find.byKey(const Key('pos-history-go-setup')), findsOneWidget);
    });
  });

  group('PosErrorScreen', () {
    testWidgets('explains the failure and offers every way out', (
      tester,
    ) async {
      final repo = FakePosRepo(
        integrations: [
          posIntegration(status: 'ERROR', lastSyncStatus: 'FAILED'),
        ],
      );
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      await pumpScreen(
        tester,
        container,
        const PosErrorScreen(message: 'Server exploded'),
      );

      expect(find.byKey(const Key('pos-error-message')), findsOneWidget);
      expect(find.text('Server exploded'), findsOneWidget);
      expect(find.byKey(const Key('pos-error-retry')), findsOneWidget);
      expect(find.byKey(const Key('pos-error-setup')), findsOneWidget);
      expect(find.byKey(const Key('pos-error-history')), findsOneWidget);
      expect(find.byKey(const Key('pos-error-back')), findsOneWidget);
    });

    testWidgets('without a connector it explains the missing link', (
      tester,
    ) async {
      final container = makeContainer(FakePosRepo());
      addTearDown(container.dispose);

      await pumpScreen(tester, container, const PosErrorScreen());

      expect(find.textContaining('no POS connector yet'), findsOneWidget);
      expect(find.text('Set up a connector'), findsOneWidget);
      expect(find.byKey(const Key('pos-error-setup')), findsOneWidget);
    });
  });
}
