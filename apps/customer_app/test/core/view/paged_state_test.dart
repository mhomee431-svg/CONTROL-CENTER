import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/view/paged_state.dart';

void main() {
  group('PagedState', () {
    test('a fresh list is initial, empty, and has nothing to append', () {
      final s = PagedState<int>();
      expect(s.items, isEmpty);
      expect(s.phase, isA<PageInitial>());
      expect(s.page, 0);
      expect(
        s.hasMore,
        isFalse,
        reason: 'an unstarted list must not invite a fetch',
      );
    });

    test('items are unmodifiable so a view cannot corrupt the list', () {
      final s = PagedState<int>(items: [1, 2]);
      expect(() => s.items.add(3), throwsUnsupportedError);
    });

    test('hasMore is DERIVED from phase, so it cannot disagree', () {
      final loading = PagedState<int>(phase: const PageLoading());
      final more = PagedState<int>(phase: const PageHasMore());
      final complete = PagedState<int>(phase: const PageComplete());
      final failed = PagedState<int>(phase: const PageFailed('x', []));

      expect(loading.hasMore, isFalse);
      expect(more.hasMore, isTrue);
      expect(complete.hasMore, isFalse);
      expect(
        failed.hasMore,
        isFalse,
        reason: 'a failed append must not immediately retry in a loop',
      );
    });

    test('loading MORE keeps the already-loaded items', () {
      final s = PagedState<int>(
        items: [1, 2, 3],
        phase: const PageLoadingMore(),
      );
      expect(
        s.items,
        [1, 2, 3],
        reason:
            'appending a page must never blank the list the customer is '
            'reading, or their scroll position resets',
      );
      expect(s.hasMore, isTrue);
    });

    test('a failed refresh retains the previous items', () {
      final previous = [1, 2];
      final s = PagedState<int>(phase: PageFailed('offline', previous));
      expect(s.phase, isA<PageFailed>());
      expect(
        (s.phase as PageFailed).previousItems,
        previous,
        reason: 'a failed refresh must not destroy visible content',
      );
    });

    test(
      'copyWith replaces the phase, keeping items unless told otherwise',
      () {
        final s = PagedState<int>(items: [1, 2], page: 1);
        final next = s.copyWith(phase: const PageLoadingMore(), page: 2);
        expect(next.items, [1, 2]);
        expect(next.page, 2);
        expect(next.phase, isA<PageLoadingMore>());
      },
    );

    test('equality is by value so a rebuild is not triggered needlessly', () {
      final a = PagedState<int>(items: const [1, 2], page: 1);
      final b = PagedState<int>(items: const [1, 2], page: 1);
      final c = PagedState<int>(items: const [1, 2], page: 2);
      final d = PagedState<int>(items: const [1, 3], page: 1);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a, isNot(d));
    });

    test('exactly one phase can be active — the boolean-cluster guarantee', () {
      const phases = <PagePhase>[
        PageInitial(),
        PageLoading(),
        PageHasMore(),
        PageLoadingMore(),
        PageComplete(),
        PageReplacing(),
        PageFailed('x', []),
      ];

      for (final p in phases) {
        final s = PagedState<int>(phase: p);
        final isHollowLoading =
            s.phase is PageLoading || s.phase is PageLoadingMore;
        final isEmptyish = s.phase is PageInitial || s.phase is PageReplacing;
        // The two failure/loading families must never overlap, which is exactly
        // what `isLoadingInitial` + `isLoadingMore` + `error` could not prevent.
        expect(
          isHollowLoading && s.phase is PageFailed,
          isFalse,
          reason: '$p cannot be both loading and failed',
        );
        expect(isHollowLoading && isEmptyish, isFalse);
      }
    });
  });
}
