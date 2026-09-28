import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/view/load_state.dart';
import 'package:hyperlocal_app/features/support/application/support_form_view_model.dart';
import 'package:hyperlocal_app/features/support/data/support_repository.dart';

/// Records what the ViewModel actually sent, so we can assert on mapping
/// (trimming, empty-email-to-null) and not only on the returned enum.
class _RecordingSupportRepository implements SupportRepository {
  _RecordingSupportRepository(this.result);

  final SupportSubmitResult result;
  int calls = 0;
  SupportIssueCategory? lastCategory;
  String? lastDescription;
  String? lastEmail;

  @override
  Future<SupportSubmitResult> submitIssue({
    required SupportIssueCategory category,
    required String description,
    String? contactEmail,
  }) async {
    calls++;
    lastCategory = category;
    lastDescription = description;
    lastEmail = contactEmail;
    return result;
  }
}

/// Violates its own contract by throwing. The ViewModel must still leave the
/// button usable, or the customer is stuck watching a spinner forever.
class _ThrowingSupportRepository implements SupportRepository {
  @override
  Future<SupportSubmitResult> submitIssue({
    required SupportIssueCategory category,
    required String description,
    String? contactEmail,
  }) async {
    throw StateError('boom');
  }
}

/// Does not complete until the test says so, so an in-flight window can be
/// observed deterministically instead of with timing guesses.
class _SlowSupportRepository implements SupportRepository {
  _SlowSupportRepository(this.completer, this.onCall);

  final Completer<SupportSubmitResult> completer;
  final void Function() onCall;

  @override
  Future<SupportSubmitResult> submitIssue({
    required SupportIssueCategory category,
    required String description,
    String? contactEmail,
  }) {
    onCall();
    return completer.future;
  }
}

ProviderContainer _containerWith(SupportRepository repo) {
  final container = ProviderContainer(
    overrides: [supportRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('SupportFormViewModel', () {
    test('starts idle, with a category and no submission in flight', () {
      final container = _containerWith(
        _RecordingSupportRepository(SupportSubmitResult.success),
      );

      final state = container.read(supportFormViewModelProvider);

      expect(state.isSubmitting, isFalse);
      expect(state.isSubmitted, isFalse);
      expect(state.errorMessage, isNull);
      expect(state.submission, isA<MutationIdle>());
    });

    test('selecting a category updates state without touching the network', () {
      final repo = _RecordingSupportRepository(SupportSubmitResult.success);
      final container = _containerWith(repo);

      container
          .read(supportFormViewModelProvider.notifier)
          .selectCategory(SupportIssueCategory.appBug);

      expect(
        container.read(supportFormViewModelProvider).category,
        SupportIssueCategory.appBug,
      );
      expect(repo.calls, 0);
    });

    test('a success reports the ticket as submitted', () async {
      final container = _containerWith(
        _RecordingSupportRepository(SupportSubmitResult.success),
      );

      final result = await container
          .read(supportFormViewModelProvider.notifier)
          .submit(description: 'Something is wrong');

      expect(result, SupportSubmitResult.success);
      expect(container.read(supportFormViewModelProvider).isSubmitted, isTrue);
    });

    test('a network failure keeps the report and offers a retry', () async {
      final container = _containerWith(
        _RecordingSupportRepository(SupportSubmitResult.networkFailure),
      );

      await container
          .read(supportFormViewModelProvider.notifier)
          .submit(description: 'Something is wrong');

      final state = container.read(supportFormViewModelProvider);
      expect(state.isSubmitted, isFalse);
      expect(state.errorMessage, isNotNull);
      expect(state.canRetry, isTrue);
    });

    test('a rejection does NOT offer retry — it would fail again', () async {
      final container = _containerWith(
        _RecordingSupportRepository(SupportSubmitResult.rejected),
      );

      await container
          .read(supportFormViewModelProvider.notifier)
          .submit(description: 'Something is wrong');

      expect(
        container.read(supportFormViewModelProvider).canRetry,
        isFalse,
        reason:
            'a Retry button that cannot change the outcome traps the '
            'customer, which the spec forbids',
      );
    });
    test('a second submit while one is in flight is ignored', () async {
      final completer = Completer<SupportSubmitResult>();
      var calls = 0;
      final container = _containerWith(
        _SlowSupportRepository(completer, () => calls++),
      );

      final notifier = container.read(supportFormViewModelProvider.notifier);
      final first = notifier.submit(description: 'first report');
      // State is MutationRunning, so a second tap must be a no-op rather than a
      // second support ticket.
      final second = notifier.submit(description: 'second report');

      completer.complete(SupportSubmitResult.success);
      await first;
      await second;

      expect(
        calls,
        1,
        reason: 'a double tap must not file two support tickets',
      );
    });

    test('a throwing repository still leaves the form usable', () async {
      final container = _containerWith(_ThrowingSupportRepository());

      await container
          .read(supportFormViewModelProvider.notifier)
          .submit(description: 'Something is wrong');

      final state = container.read(supportFormViewModelProvider);
      expect(
        state.isSubmitting,
        isFalse,
        reason: 'an uncaught throw would leave the button spinning forever',
      );
      expect(state.errorMessage, isNotNull);
    });

    test('description is trimmed and a blank email becomes null', () async {
      final repo = _RecordingSupportRepository(SupportSubmitResult.success);
      final container = _containerWith(repo);

      await container
          .read(supportFormViewModelProvider.notifier)
          .submit(description: '   padded report   ', contactEmail: '   ');

      expect(repo.lastDescription, 'padded report');
      expect(
        repo.lastEmail,
        isNull,
        reason: 'an empty email must be omitted, not sent as whitespace',
      );
    });

    test('reset returns the form to its initial state', () async {
      final container = _containerWith(
        _RecordingSupportRepository(SupportSubmitResult.success),
      );

      final notifier = container.read(supportFormViewModelProvider.notifier);
      await notifier.submit(description: 'Something is wrong');
      notifier.reset();

      final state = container.read(supportFormViewModelProvider);
      expect(state.isSubmitted, isFalse);
      expect(state.submission, isA<MutationIdle>());
    });
  });
}
