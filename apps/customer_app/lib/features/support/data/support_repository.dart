import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_error_handler.dart' show ApiErrorType, ApiException;

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
/// server" and "the server rejected this" are distinguishable, and so a
/// caller cannot accidentally treat a failure as success.
enum SupportSubmitResult {
  /// The server accepted the ticket.
  success,

  /// The request never reached the server (offline, DNS, timeout).
  networkFailure,

  /// The server received it but refused (validation, 4xx/5xx).
  rejected,
}

/// Provider — wired to the real backend.
final supportRepositoryProvider = Provider<SupportRepository>((ref) {
  return ApiSupportRepository(ref.watch(apiClientProvider));
});

/// Abstract contract — lets tests inject a mock easily.
abstract class SupportRepository {
  /// Attempts to submit a support issue.
  ///
  /// Never throws: every outcome is reported as a [SupportSubmitResult] so
  /// the UI is forced to handle the failure cases explicitly.
  Future<SupportSubmitResult> submitIssue({
    required SupportIssueCategory category,
    required String description,
    String? contactEmail,
  });
}

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
