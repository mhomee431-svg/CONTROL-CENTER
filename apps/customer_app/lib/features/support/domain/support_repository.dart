/// The support-ticket contract, in the DOMAIN layer.
///
/// WHY THIS FILE EXISTS
/// --------------------
/// The interface, the category enum, and the result enum used to live in
/// `data/support_repository.dart` next to the Dio implementation. That put the
/// CONTRACT inside the layer that implements it, which had two consequences:
///
/// 1. A view that only needed to name a category had to import `data/`,
///    because that is where the enum was — a View-rule violation caused purely
///    by file placement, not by design.
/// 2. The contract could not be depended on without dragging in `ApiClient`,
///    `ApiEndpoints` and Dio, so a plain unit test of any consumer pulled the
///    whole HTTP stack along with it.
///
/// The implementation stays in `data/`. Only the vocabulary moves, so `domain`
/// stays free of IO and Dio.
library;

import 'models/support_issue.dart';

/// Issue categories the customer can choose when filing a support ticket.
enum SupportIssueCategory {
  wrongInformation('Wrong product/shop information'),
  availabilityMismatch('Availability mismatch'),
  appBug('App bug or crash'),
  dataPrivacy('Data / privacy concern'),
  accountIssue('Account issue'),
  other('Other');

  const SupportIssueCategory(this.label);
  final String label;
}

/// Result of a support-ticket submission.
///
/// Modelled as a type rather than a bare `bool` so "we could not reach the
/// server" and "the server rejected this" are distinguishable, and so a caller
/// cannot accidentally treat a failure as success.
///
/// The three cases also drive different customer-facing copy, which is why they
/// are not collapsed: a network failure should offer "check your connection",
/// while a rejection should tell the customer support will look at it.
enum SupportSubmitResult {
  /// The server accepted the ticket.
  success,

  /// The request never reached the server (offline, DNS, timeout).
  networkFailure,

  /// The server received it but refused (validation, 4xx/5xx).
  rejected,
}

/// The support contract.
///
/// Implemented by `ApiSupportRepository` (data) and by a fake in tests.
abstract class SupportRepository {
  /// Attempts to submit a support issue.
  ///
  /// Never throws: every outcome is reported as a [SupportSubmitResult] so the
  /// UI is forced to handle the failure cases explicitly.
  Future<SupportSubmitResult> submitIssue({
    required SupportIssueCategory category,
    required String description,
    String? contactEmail,
  });

  /// The tickets THIS customer has filed, newest first (`GET /support/issues`).
  ///
  /// The READ half of the same resource `submitIssue` writes to. It exists
  /// because a report the customer cannot look up again is not really filed
  /// from their point of view: without this, "we have your report" was the last
  /// word the app ever had on the subject.
  ///
  /// Scoping is the BACKEND's: the route filters on the authenticated reporter,
  /// so no query parameter here can widen it to another customer's tickets.
  ///
  /// Unlike [submitIssue] this MAY throw — a failed read is surfaced so the
  /// screen can offer a retry, rather than being silently reported as "you have
  /// no reports", which would be a lie the customer would act on.
  Future<List<SupportIssue>> listMyIssues();
}

/// User-safe copy for each outcome.
///
/// Lives in domain because choosing what a CUSTOMER reads is a product decision,
/// not an HTTP concern. The view renders this string; it never composes its own
/// error text from an exception.
extension SupportSubmitResultCopy on SupportSubmitResult {
  String get userMessage => switch (this) {
    SupportSubmitResult.success =>
      'Thanks — we have your report and will look into it.',
    SupportSubmitResult.networkFailure =>
      'We could not reach our servers. Check your connection and try again.',
    SupportSubmitResult.rejected =>
      'We could not accept that report. Please try again, or email us from the '
          'Contact tab.',
  };

  /// Whether offering the customer a retry button makes sense.
  ///
  /// A rejection will be rejected again unchanged, so a Retry button there is a
  /// trap — the exact thing the spec forbids ("do not trap the customer").
  bool get isRetryable => this == SupportSubmitResult.networkFailure;
}
