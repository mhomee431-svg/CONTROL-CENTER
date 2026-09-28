import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/network/connectivity_service.dart';

/// The tri-state state machine that decides what the customer is told about
/// their connection.
///
/// The rule under test throughout: the app must never claim connectivity it
/// has not proven. A transport flag alone is not proof — it stays "connected"
/// on a captive portal or a dead uplink — so `reconnecting` exists as a
/// distinct, honest middle state.
void main() {
  late DateTime clock;
  late ConnectivityService service;

  setUp(() {
    clock = DateTime(2026, 9, 27, 12, 0, 0);
    service = ConnectivityService(
      Connectivity(),
      now: () => clock,
    );
  });

  tearDown(() {
    // Every test arms a real reconnect timer; without disposal the test
    // harness would keep the timer alive and complain about a pending timer.
    service.dispose();
  });

  group('ConnectivityService transport mapping', () {
    test('a connected transport alone does not claim online', () {
      // The transport flag is not proof of internet access. A first report of
      // "wifi" must leave the app neutral rather than telling the customer
      // everything is fine before anything has actually succeeded.
      expect(
        service.applyTransportResults([ConnectivityResult.wifi]),
        ConnectivityStatus.unknown,
      );
      expect(service.isConnected, isFalse);
    });

    test('the first successful request promotes unknown to online', () {
      service.applyTransportResults([ConnectivityResult.wifi]);
      expect(service.status, ConnectivityStatus.unknown);

      // Real traffic is the only proof.
      service.confirmReachable();
      expect(service.status, ConnectivityStatus.online);
      expect(service.isConnected, isTrue);
    });

    test('a connected transport after a proven connection stays online', () {
      service.confirmReachable();
      expect(
        service.applyTransportResults([ConnectivityResult.wifi]),
        ConnectivityStatus.online,
      );
    });

    test('no transport at all is offline', () {
      expect(
        service.applyTransportResults([ConnectivityResult.none]),
        ConnectivityStatus.offline,
      );
    });

    test('multiple transports with one live still counts as online', () {
      // A device can hold a stale wifi entry alongside a working cellular one;
      // treating that as offline would be wrong.
      service.confirmReachable();
      expect(
        service.applyTransportResults([
          ConnectivityResult.none,
          ConnectivityResult.mobile,
        ]),
        ConnectivityStatus.online,
      );
    });

    test('returning transport enters reconnecting, not online', () {
      service.applyTransportResults([ConnectivityResult.none]);
      expect(service.status, ConnectivityStatus.offline);

      // Transport is back, but nothing has proven it actually works.
      expect(
        service.applyTransportResults([ConnectivityResult.wifi]),
        ConnectivityStatus.reconnecting,
      );
    });

    test('a successful request promotes reconnecting to online', () {
      service.applyTransportResults([ConnectivityResult.none]);
      service.applyTransportResults([ConnectivityResult.wifi]);
      expect(service.status, ConnectivityStatus.reconnecting);

      service.confirmReachable();
      expect(service.status, ConnectivityStatus.online);
      // And a later transport report must not regress it to reconnecting.
      expect(
        service.applyTransportResults([ConnectivityResult.wifi]),
        ConnectivityStatus.online,
      );
    });

    test('reconnecting gives up to offline when the transport never works', () {
      // A captive portal reports "connected" while nothing is reachable.
      // Without this deadline the UI would claim "Reconnecting…" indefinitely.
      service.applyTransportResults([ConnectivityResult.none]);
      clock = clock.add(ConnectivityService.reconnectTimeout);
      expect(
        service.applyTransportResults([ConnectivityResult.wifi]),
        ConnectivityStatus.offline,
      );
    });

    test('a request failure while online marks the device offline', () {
      // Transport can lie: the flag says wifi, the request still fails.
      service.confirmReachable();
      expect(service.status, ConnectivityStatus.online);

      service.noteRequestFailure();
      expect(service.status, ConnectivityStatus.offline);
    });

    test('a request failure while unknown marks the device offline', () {
      // The very first request can be the one that reveals there is no network.
      // Reporting that as "unknown" forever would strand the customer behind a
      // screen that never explains why nothing loads.
      expect(service.status, ConnectivityStatus.unknown);

      service.noteRequestFailure();
      expect(service.status, ConnectivityStatus.offline);
    });

    test('reconnecting is not reported as connected', () {
      service.applyTransportResults([ConnectivityResult.none]);
      service.applyTransportResults([ConnectivityResult.wifi]);

      // The whole point of the tri-state: unproven is not proven.
      expect(service.isConnected, isFalse);
      expect(service.isOnline, isFalse);
    });
  });

  group('ConnectivityService broadcasting', () {
    test('a successful request is broadcast, not silently applied', () async {
      // The regression this guards: state changed internally but nothing
      // reached the stream, so the banner stayed on "Reconnecting…" forever
      // even though the request that ended it had succeeded.
      final seen = <ConnectivityStatus>[];
      final sub = service.onStatusChanged.listen(seen.add);
      await pumpEventQueue();

      service.applyTransportResults([ConnectivityResult.none]);
      service.applyTransportResults([ConnectivityResult.wifi]);
      service.confirmReachable();
      await pumpEventQueue();

      expect(seen, [
        ConnectivityStatus.unknown,
        ConnectivityStatus.offline,
        ConnectivityStatus.reconnecting,
        ConnectivityStatus.online,
      ]);
      await sub.cancel();
    });

    test('a request failure is broadcast', () async {
      final seen = <ConnectivityStatus>[];
      final sub = service.onStatusChanged.listen(seen.add);
      await pumpEventQueue();

      service.confirmReachable();
      service.noteRequestFailure();
      await pumpEventQueue();

      expect(seen, [
        ConnectivityStatus.unknown,
        ConnectivityStatus.online,
        ConnectivityStatus.offline,
      ]);
      await sub.cancel();
    });

    test('repeating a state does not re-emit it', () async {
      final seen = <ConnectivityStatus>[];
      final sub = service.onStatusChanged.listen(seen.add);
      await pumpEventQueue();

      service.applyTransportResults([ConnectivityResult.none]);
      service.applyTransportResults([ConnectivityResult.none]);
      await pumpEventQueue();

      // One offline event, not two: a redundant rebuild for an unchanged state.
      expect(
        seen.where((s) => s == ConnectivityStatus.offline).length,
        1,
      );
      await sub.cancel();
    });
  });

  group('ConnectivityService reconnect deadline', () {
    // Uses `fakeAsync` so the 12-second deadline is verified in virtual time.
    // Awaiting it for real added ~40s of pure wall-clock to the suite while
    // proving nothing extra: the behaviour under test is the timer firing, not
    // the clock.
    test('reconnecting expires to offline on its own, with no new event', () {
      // The bug this guards: the deadline was only ever evaluated when the next
      // transport event happened to arrive. A captive portal that reports
      // "connected" once and then goes silent left the UI on "Reconnecting…"
      // indefinitely.
      fakeAsync((async) {
        service.applyTransportResults([ConnectivityResult.none]);
        service.applyTransportResults([ConnectivityResult.wifi]);
        expect(service.status, ConnectivityStatus.reconnecting);

        async.elapse(ConnectivityService.reconnectTimeout);
        expect(service.status, ConnectivityStatus.offline);
      });
    });

    test('a request arriving before the deadline keeps the app online', () {
      fakeAsync((async) {
        service.applyTransportResults([ConnectivityResult.none]);
        service.applyTransportResults([ConnectivityResult.wifi]);
        expect(service.status, ConnectivityStatus.reconnecting);

        // The connection genuinely works; the timer must not later overwrite
        // that truth and claim we are offline.
        service.confirmReachable();
        expect(service.status, ConnectivityStatus.online);

        async.elapse(ConnectivityService.reconnectTimeout * 3);
        expect(service.status, ConnectivityStatus.online);
      });
    });

    test('dispose cancels the deadline so it cannot fire afterwards', () {
      fakeAsync((async) {
        service.applyTransportResults([ConnectivityResult.none]);
        service.applyTransportResults([ConnectivityResult.wifi]);
        expect(service.status, ConnectivityStatus.reconnecting);

        service.dispose();
        async.elapse(ConnectivityService.reconnectTimeout * 3);

        // A disposed service must not mutate or emit. If the timer survived,
        // `status` would have flipped to offline and the closed controller
        // would have thrown a Bad state error.
        expect(service.status, ConnectivityStatus.reconnecting);
      });
    });

    test('repeated transport events do not stack multiple deadlines', () {
      fakeAsync((async) {
        service.applyTransportResults([ConnectivityResult.none]);
        // Several "transport is back" reports in quick succession.
        for (var i = 0; i < 5; i++) {
          service.applyTransportResults([ConnectivityResult.wifi]);
          async.elapse(const Duration(seconds: 1));
        }

        // Each event re-armed (rather than added to) the single timer, so the
        // deadline runs from the latest report and expires exactly once.
        async.elapse(ConnectivityService.reconnectTimeout);
        expect(service.status, ConnectivityStatus.offline);
      });
    });
  });
}
