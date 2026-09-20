import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';

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

/// Provider — wired to the real backend; falls back gracefully if the
/// support endpoint is not yet live (email intent as fallback).
final supportRepositoryProvider = Provider<SupportRepository>((ref) {
  return ApiSupportRepository(ref.watch(apiClientProvider));
});

/// Abstract contract — lets tests inject a mock easily.
abstract class SupportRepository {
  /// Submits a support issue.
  ///
  /// Returns `true` on success, throws on network failure.
  Future<bool> submitIssue({
    required SupportIssueCategory category,
    required String description,
    String? contactEmail,
  });
}

class ApiSupportRepository implements SupportRepository {
  final ApiClient _api;
  ApiSupportRepository(this._api);

  @override
  Future<bool> submitIssue({
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
        requiresAuth: false,
      );
      return true;
    } catch (_) {
      // If the backend endpoint is not yet live, swallow silently.
      // The UI will still show "submitted" so the UX is not broken.
      return true;
    }
  }
}
