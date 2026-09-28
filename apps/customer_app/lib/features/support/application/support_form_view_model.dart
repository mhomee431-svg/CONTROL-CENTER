import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/view/load_state.dart';
import '../../../core/view/view_model.dart';
// The data barrel re-exports the domain vocabulary, so one import covers both
// the provider and the enums — importing both would be flagged as redundant.
import '../data/support_repository.dart';

export '../domain/support_repository.dart'
    show SupportIssueCategory, SupportSubmitResult, SupportSubmitResultCopy;

/// Everything the support form needs to render itself.
///
/// The form's TEXT stays in the widget — a `TextEditingController` is widget
/// state by definition and putting it here would mean a ViewModel importing
/// `material.dart`. What moves out is the part that was genuinely business
/// logic living in the view: the mutation state machine and the decision of
/// which copy a customer sees.
class SupportFormState {
  /// Which category the customer picked.
  final SupportIssueCategory category;

  /// The mutation lifecycle. One case at a time — never two booleans.
  final MutationState submission;

  const SupportFormState({
    this.category = SupportIssueCategory.wrongInformation,
    this.submission = const MutationIdle(),
  });

  bool get isSubmitting => submission.isRunning;

  /// True once the server has actually acknowledged the ticket.
  ///
  /// Derived from [MutationSucceeded] rather than a `_submitted` bool, so it
  /// cannot be set optimistically. A customer must never be shown "we have your
  /// report" for a request that never landed.
  bool get isSubmitted => submission is MutationSucceeded;

  /// User-safe failure text, or null when there is no failure to show.
  String? get errorMessage => switch (submission) {
    MutationFailed(:final message) => message,
    _ => null,
  };

  /// Whether a Retry button should be offered.
  ///
  /// Only for a network failure. A rejection will be rejected again, so a Retry
  /// there is a trap.
  bool get canRetry => switch (submission) {
    MutationFailed(:final error) => (error as SupportSubmitResult).isRetryable,
    _ => false,
  };

  SupportFormState copyWith({
    SupportIssueCategory? category,
    MutationState? submission,
  }) {
    return SupportFormState(
      category: category ?? this.category,
      submission: submission ?? this.submission,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupportFormState &&
          category == other.category &&
          submission == other.submission;

  @override
  int get hashCode => Object.hash(category, submission);
}

/// Owns the support-ticket submission.
///
/// This is the ViewModel the View rule asks for: the screen used to call
/// `supportRepository.submitIssue` itself and hold `_isSubmitting` / `_error` /
/// `_submitted` as three independent `setState` fields, which could represent
/// "submitting" and "failed" simultaneously and let a double tap fire two
/// tickets. [MutationState] makes that unrepresentable, and `submit` returns
/// early when a request is already in flight.
class SupportFormViewModel extends ViewModel<SupportFormState> {
  @override
  SupportFormState buildOnce() => const SupportFormState();

  /// Records the chosen category. A display decision with no IO.
  void selectCategory(SupportIssueCategory category) {
    state = state.copyWith(category: category);
  }

  /// Submits a ticket.
  ///
  /// [description] and [contactEmail] are passed in rather than read from a
  /// controller held here, which is what keeps this class free of Flutter
  /// widgets.
  Future<SupportSubmitResult?> submit({
    required String description,
    String? contactEmail,
  }) async {
    // The duplicate-ticket guard. Two taps must not create two support tickets.
    if (state.isSubmitting) return null;

    state = state.copyWith(submission: const MutationRunning());
    final repository = ref.read(supportRepositoryProvider);

    try {
      final result = await repository.submitIssue(
        category: state.category,
        description: description.trim(),
        contactEmail: (contactEmail ?? '').trim().isEmpty
            ? null
            : contactEmail!.trim(),
      );

      state = state.copyWith(
        submission: result == SupportSubmitResult.success
            ? const MutationSucceeded()
            : MutationFailed(result, result.userMessage),
      );
      return result;
    } catch (error) {
      // The repository contract says it never throws, but a fake in a test, or a
      // future implementation, might. An uncaught throw here would leave the
      // button spinning forever, which is the one outcome the customer cannot
      // escape — so the catch is deliberate, not defensive noise.
      //
      // The stack is intentionally NOT bound: it would be an unused-catch-stack
      // warning, and the raw error is already carried on `MutationFailed` for
      // logging by whoever renders the failure.
      state = state.copyWith(
        submission: MutationFailed(
          error,
          SupportSubmitResult.networkFailure.userMessage,
        ),
      );
      return null;
    }
  }

  /// Returns the form to its initial state, e.g. after the customer edits the
  /// description following a failure.
  void reset() {
    state = buildOnce();
  }
}

/// The form ViewModel. Hot by default (see [ViewModel]), so returning to the
/// screen does not discard a half-written description's submission outcome.
final supportFormViewModelProvider =
    NotifierProvider<SupportFormViewModel, SupportFormState>(
      SupportFormViewModel.new,
    );
