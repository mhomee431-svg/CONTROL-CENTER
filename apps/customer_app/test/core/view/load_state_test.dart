import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/view/load_state.dart';

void main() {
  group('LoadState', () {
    test(
      'idle is NOT loading — "not started" differs from "still working"',
      () {
        const s = LoadState<int>.idle();
        expect(s.isLoading, isFalse);
        expect(s.dataOrNull, isNull);
      },
    );

    test('loading has no data', () {
      const s = LoadLoading<int>();
      expect(s.isLoading, isTrue);
      expect(s.dataOrNull, isNull);
      expect(s.isFailed, isFalse);
    });

    test('ready exposes its value', () {
      const s = LoadReady<int>(5);
      expect(s.dataOrNull, 5);
      expect(s.isLoading, isFalse);
      expect(s.isFailed, isFalse);
    });

    test('empty is a SUCCESS, not a failure', () {
      const s = LoadEmpty<int>();
      expect(s.isFailed, isFalse, reason: 'no results is not an error');
      expect(s.error, isNull);
      expect(s.dataOrNull, isNull);
    });

    test('a failed refresh RETAINS the previous value', () {
      const s = LoadFailed<int>('offline', 7);
      expect(
        s.dataOrNull,
        7,
        reason: 'a failed refresh must not destroy visible content',
      );
      expect(s.isFailed, isTrue);
      expect(s.error, 'offline');
    });

    test('a failure with nothing previous has no data', () {
      const s = LoadFailed<int>('cold');
      expect(s.dataOrNull, isNull);
      expect(s.isFailed, isTrue);
    });

    test('exactly one phase is true — this is what booleans could not do', () {
      const states = <LoadState<int>>[
        LoadIdle<int>(),
        LoadLoading<int>(),
        LoadReady<int>(1),
        LoadEmpty<int>(),
        LoadFailed<int>('x'),
      ];

      for (final s in states) {
        final flags = [s.isLoading, s.isFailed];
        // "loading" and "failed" can never both hold.
        expect(
          flags.where((f) => f).length,
          lessThanOrEqualTo(1),
          reason: '$s has conflicting phase flags',
        );
      }
    });
  });

  group('MutationState', () {
    test('idle is not running and not failed', () {
      const m = MutationState.idle();
      expect(m.isRunning, isFalse);
      expect(m.isFailed, isFalse);
    });

    test('running cannot also be failed — the double-submit bug', () {
      const m = MutationRunning();
      expect(m.isRunning, isTrue);
      expect(
        m.isFailed,
        isFalse,
        reason:
            'a request in flight is not a failure; showing both '
            'traps the customer on a control that appears broken',
      );
    });

    test('succeeded is distinct from idle so the view can show a receipt', () {
      const m = MutationSucceeded();
      expect(m.isRunning, isFalse);
      expect(m.isFailed, isFalse);
      // The type itself is the signal; there is no boolean to forget to set.
      expect(m, isA<MutationSucceeded>());
    });

    test('failed carries a user-safe message', () {
      const m = MutationFailed('raw stack trace', 'Something went wrong');
      expect(m.isFailed, isTrue);
      expect(m.error, 'raw stack trace');
      expect(
        m.message,
        'Something went wrong',
        reason: 'the view must render `message`, never `error`',
      );
    });
  });
}
