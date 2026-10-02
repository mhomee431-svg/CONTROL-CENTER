/// The Dio-backed implementation of [SupportRepository].
///
/// The CONTRACT (interface, enums, user-facing copy) lives in
/// `../domain/support_repository.dart`; only the HTTP wiring is here. That split
/// is what lets a view depend on the support vocabulary without importing a data
/// layer, and lets a unit test construct a fake without pulling in Dio.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_error_handler.dart'
    show ApiErrorType, ApiException;
import '../../../core/network/json_map.dart';
import '../domain/models/support_issue.dart';
import '../domain/support_repository.dart';

export '../domain/models/support_issue.dart';
export '../domain/support_repository.dart'
    show
        SupportIssueCategory,
        SupportRepository,
        SupportSubmitResult,
        SupportSubmitResultCopy;

/// Provider — wired to the real backend.
final supportRepositoryProvider = Provider<SupportRepository>((ref) {
  return ApiSupportRepository(ref.watch(apiClientProvider));
});

class ApiSupportRepository implements SupportRepository {
  final ApiClient _api;
  ApiSupportRepository(this._api);

  @override
  Future<SupportSubmitResult> submitIssue({
    required SupportIssueCategory category,
    required String description,
    String? contactEmail,
  }) async {
    try {
      await _api.post(
        ApiEndpoints.supportIssue,
        data: {
          'category': category.name,
          'description': description,
          if (contactEmail != null && contactEmail.isNotEmpty)
            'contact_email': contactEmail,
        },
        // The customer must be signed in: the ticket is attached to their
        // account so support can follow up.
        requiresAuth: true,
      );
      return SupportSubmitResult.success;
    } on ApiException catch (e) {
      // A structured API error means the server answered — it just said no.
      // Reporting that as "submitted" (as this method used to) is a lie the
      // customer would act on.
      return switch (e.type) {
        ApiErrorType.offline ||
        ApiErrorType.timeout ||
        ApiErrorType.requestCancelled => SupportSubmitResult.networkFailure,
        _ => SupportSubmitResult.rejected,
      };
    } catch (_) {
      return SupportSubmitResult.networkFailure;
    }
  }

  /// The customer's own reported issues (`GET /support/issues`).
  ///
  /// Reads the `tickets` list out of the envelope. A response whose `tickets`
  /// is missing or is not a list yields an EMPTY list rather than throwing: the
  /// backend answers `{tickets: [], count: 0, total: 0}` for a customer who has
  /// never reported anything, and an unreadable payload is not evidence of a
  /// report. A transport failure still propagates (see the domain contract) so
  /// the screen can distinguish "nothing reported" from "could not load".
  @override
  Future<List<SupportIssue>> listMyIssues() async {
    final data = await _api.get(
      ApiEndpoints.supportIssue,
      // Attached to the signed-in customer's account. The backend scopes the
      // query to the authenticated reporter, so there is no parameter here that
      // could widen it.
      requiresAuth: true,
    );

    final tickets = data is Map ? data['tickets'] : null;
    if (tickets is! List) return const [];

    // A row that cannot be read as a ticket is dropped rather than rendered
    // blank — `tryParse` returns null for a payload with no usable id, because
    // that ticket has no reference the customer could quote to support.
    final issues = <SupportIssue>[];
    for (final entry in tickets) {
      final issue = SupportIssue.tryParse(JsonMap.tryParse(entry));
      if (issue != null) issues.add(issue);
    }
    return issues;
  }
}
