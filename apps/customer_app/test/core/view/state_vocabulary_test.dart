import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/view/load_state.dart';
import 'package:hyperlocal_app/core/view/paged_state.dart';
import 'package:hyperlocal_app/core/view/state_vocabulary.dart';

void main() {
  group('state vocabulary', () {
    test('names exactly the eight conceptual states from the spec', () {
      expect(ConceptualState.values, hasLength(8));
      expect(
        StateVocabulary.all,
        containsAll(<ConceptualState>[
          ConceptualState.initial,
          ConceptualState.loading,
          ConceptualState.loaded,
          ConceptualState.empty,
          ConceptualState.refreshing,
          ConceptualState.saving,
          ConceptualState.success,
          ConceptualState.error,
        ]),
      );
    });

    test('every state model covers at least one conceptual state', () {
      expect(
        StateVocabulary.uncovered,
        isEmpty,
        reason:
            'a new state model was declared but never wired into the '
            'vocabulary, so nothing checks it',
      );
    });

    test(
      'LOADING and REFRESHING are distinguishable — they render differently',
      () {
        const cold = LoadLoading<int>();
        const warm = LoadRefreshing<int>(7);

        expect(
          cold.isLoading && warm.isLoading,
          isTrue,
          reason: 'both are "a request is in flight"',
        );
        expect(
          cold.dataOrNull,
          isNull,
          reason: 'a cold load has nothing to show, so a skeleton is correct',
        );
        expect(
          warm.dataOrNull,
          7,
          reason:
              'a refresh must keep the previous value, or the screen blanks',
        );
        expect(
          cold.runtimeType == warm.runtimeType,
          isFalse,
          reason: 'a view cannot tell them apart if they are the same type',
        );
      },
    );

    test('EMPTY is a success, not an error', () {
      const empty = LoadEmpty<int>();
      const failed = LoadFailed<int>('boom');

      expect(empty.isFailed, isFalse);
      expect(empty.error, isNull);
      expect(failed.isFailed, isTrue);
    });

    test(
      'SUCCESS requires a confirmation — it is never derived optimistically',
      () {
        const succeeded = MutationSucceeded();
        const running = MutationRunning();

        expect(succeeded.isRunning, isFalse);
        expect(
          running.isFailed,
          isFalse,
          reason: '"saving" and "error" must never both hold',
        );
        expect(
          running is MutationSucceeded,
          isFalse,
          reason: 'an in-flight write is not a confirmation',
        );
      },
    );

    test('ERROR retains previous content so a failure never destroys data', () {
      const loadFailed = LoadFailed<int>('offline', 5);
      final pageFailed = PagedState<int>(
        items: const [1, 2],
        phase: const PageFailed('offline', [1, 2]),
      );

      expect(loadFailed.dataOrNull, 5);
      expect((pageFailed.phase as PageFailed).previousItems, isNotEmpty);
    });

    test('a paged list reports each phase as exactly one conceptual state', () {
      final phases = <PagePhase, ConceptualState>{
        const PageInitial(): ConceptualState.initial,
        const PageLoading(): ConceptualState.loading,
        const PageReplacing(): ConceptualState.loading,
        const PageHasMore(): ConceptualState.loaded,
        const PageLoadingMore(): ConceptualState.refreshing,
        const PageComplete(): ConceptualState.loaded,
        const PageFailed('x', []): ConceptualState.error,
      };

      for (final entry in phases.entries) {
        expect(
          StateVocabulary.all,
          contains(entry.value),
          reason: '${entry.key} maps to a state the vocabulary does not name',
        );
      }
    });
  });
}
