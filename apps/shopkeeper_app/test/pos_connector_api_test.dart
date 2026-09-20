import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/pos/data/pos_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/pos/domain/pos_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/pos/presentation/controllers/pos_controller.dart';

import 'fakes.dart';

/// The connector API surface beyond load/connect/sync: terminals, schedule,
/// vendor-neutral sync settings, job diagnostics and the retry path.
void main() {
  ProviderContainer makeContainer(FakePosRepo repo, {int? shopId = 10}) {
    final container = ProviderContainer(overrides: [
      posRepositoryProvider.overrideWithValue(repo),
      tokenStoreProvider.overrideWithValue(
          InMemoryTokenStore(accessToken: 'test-access-token')),
      selectedShopProvider.overrideWith(
        () =>
            SelectedShopOverride(shopId == null ? null : ownerShop(id: shopId)),
      ),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  Future<PosState> loadConnected(FakePosRepo repo, ProviderContainer c) async {
    await c.read(posControllerProvider.notifier).load();
    return c.read(posControllerProvider);
  }

  group('Sync schedule (PUT .../schedule)', () {
    test('pausing and resuming background sync reaches the server', () async {
      final repo = FakePosRepo(integrations: [posIntegration()]);
      final container = makeContainer(repo);
      await loadConnected(repo, container);

      final paused = await container
          .read(posControllerProvider.notifier)
          .updateSchedule(syncEnabled: false);

      expect(paused, isTrue);
      expect(repo.scheduleCalls, 1);
      expect(repo.lastSchedule?.syncEnabled, isFalse);
      expect(repo.lastSchedule?.syncIntervalMinutes, isNull);
    });

    test('changing the cadence reaches the server', () async {
      final repo = FakePosRepo(integrations: [posIntegration()]);
      final container = makeContainer(repo);
      await loadConnected(repo, container);

      final ok = await container
          .read(posControllerProvider.notifier)
          .updateSchedule(intervalMinutes: 30);

      expect(ok, isTrue);
      expect(repo.lastSchedule?.syncIntervalMinutes, 30);
    });

    test('without a connector there is nothing to schedule', () async {
      final repo = FakePosRepo();
      final container = makeContainer(repo);
      await loadConnected(repo, container);

      final ok = await container
          .read(posControllerProvider.notifier)
          .updateSchedule(syncEnabled: false);

      expect(ok, isFalse);
      expect(repo.scheduleCalls, 0);
    });
  });

  group('Sync settings (PUT .../config)', () {
    test('sends ONLY the knobs the sheet offers, never the whole bag',
        () async {
      final repo = FakePosRepo(integrations: [posIntegration()]);
      final container = makeContainer(repo);
      await loadConnected(repo, container);

      final ok = await container
          .read(posControllerProvider.notifier)
          .updateSyncSettings(const PosSyncSettings(
            batchSize: 250,
            fieldAuthorities: {'inventory': 'POS', 'price': 'PLATFORM'},
          ));

      expect(ok, isTrue);
      expect(repo.configCalls, 1);
      final sent = repo.lastSyncSettings!;
      expect(sent.batchSize, 250);
      expect(sent.authorityFor('inventory'), 'POS');
      // An unlisted field keeps the backend default - never invented here.
      expect(sent.authorityFor('barcode'), 'PLATFORM');
    });

    test('the request body carries the deep-merged config keys', () {
      const settings = PosSyncSettings(
        batchSize: 100,
        fieldAuthorities: {'inventory': 'POS'},
      );
      expect(settings.toRequest(), {
        'batch_size': 100,
        'field_authorities': {'inventory': 'POS'},
      });
    });
  });

  group('Terminals (GET/POST .../devices)', () {
    test('mapping a terminal reloads the list and the device count', () async {
      final repo = FakePosRepo(integrations: [posIntegration()]);
      final container = makeContainer(repo);
      await loadConnected(repo, container);

      final ok = await container
          .read(posControllerProvider.notifier)
          .registerTerminal(
            deviceIdentifier: 'TILL-01',
            deviceName: 'Counter 1',
            deviceType: 'POS_TERMINAL',
          );

      expect(ok, isTrue);
      expect(repo.registerDeviceCalls, 1);
      expect(repo.listDevicesCalls, 1);
      expect(container.read(posControllerProvider).devices, hasLength(1));
      expect(container.read(posControllerProvider).devices.first.displayName,
          'Counter 1');
    });

    test('a refused mapping is reported without blanking the connector',
        () async {
      final repo = FakePosRepo(integrations: [posIntegration()])
        ..devicesError = const ApiException(
          statusCode: 403,
          message: 'Only shop owners can manage POS terminals.',
        );
      final container = makeContainer(repo);
      await loadConnected(repo, container);

      final ok = await container
          .read(posControllerProvider.notifier)
          .registerTerminal(deviceIdentifier: 'TILL-01');

      expect(ok, isFalse);
      final state = container.read(posControllerProvider);
      expect(state.status, PosStatus.ready);
      expect(state.integration, isNotNull);
      expect(state.message, 'Only shop owners can manage POS terminals.');
    });
  });

  group('Job diagnostics + retry', () {
    test('job detail carries the logs and mapping conflicts', () async {
      final repo = FakePosRepo(integrations: [posIntegration()]);
      final container = makeContainer(repo);
      await loadConnected(repo, container);

      final detail =
          await container.read(posControllerProvider.notifier).jobDetail(900);

      expect(repo.jobDetailCalls, 1);
      expect(detail, isNotNull);
      expect(detail!.job.id, 900);
      expect(detail.logs, hasLength(2));
      expect(detail.logs.first.isError, isTrue);
      expect(detail.conflicts, hasLength(1));
      expect(detail.conflicts.first.field, 'price');
      expect(detail.conflicts.first.platformValue, '120.00');
      expect(detail.hasDiagnostics, isTrue);
    });

    test('retrying a failed job refreshes status and history', () async {
      final repo = FakePosRepo(integrations: [posIntegration()]);
      final container = makeContainer(repo);
      await loadConnected(repo, container);
      final jobsBefore = repo.jobsCalls;

      final retried = await container
          .read(posControllerProvider.notifier)
          .retryFailedJob(900);

      expect(retried, isNotNull);
      expect(repo.retryCalls, 1);
      expect(repo.jobsCalls, greaterThan(jobsBefore));
    });

    test('a retry the backend refuses is reported, not swallowed', () async {
      final repo = FakePosRepo(integrations: [posIntegration()])
        ..retryError = const ApiException(
          statusCode: 409,
          message: 'POS integration is disconnected',
        );
      final container = makeContainer(repo);
      await loadConnected(repo, container);

      final retried = await container
          .read(posControllerProvider.notifier)
          .retryFailedJob(900);

      expect(retried, isNull);
      final state = container.read(posControllerProvider);
      expect(state.status, PosStatus.ready);
      expect(state.message, 'POS integration is disconnected');
    });
  });
}