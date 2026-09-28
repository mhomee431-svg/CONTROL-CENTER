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
import '../domain/support_repository.dart';

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
}
