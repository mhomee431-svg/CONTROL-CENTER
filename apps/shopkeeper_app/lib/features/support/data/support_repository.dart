import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_providers.dart';
import '../domain/support_models.dart';
import '../domain/support_ticket.dart';

/// Support-ticket contract for the signed-in shopkeeper.
///
/// Backed by the real `/shopkeeper/support/tickets` routes, which store tickets
/// in the platform's `complaints` table (the same queue the admin console
/// triages — see `backend/app/services/support_service.py`).
abstract class SupportRepository {
  /// Files a ticket and returns it as stored, INCLUDING the backend's status.
  ///
  /// [steps], [appVersion] and [shopId] are optional context: the backend folds
  /// them into the stored report so support triages from one body.
  /// [attachmentKey] is the key returned by [uploadAttachment]; the backend
  /// re-validates it before storing it.
  Future<SupportTicket> createTicket({
    required String token,
    required IssueCategory category,
    required IssueSeverity severity,
    required String description,
    String? steps,
    String? appVersion,
    int? shopId,
    String? attachmentKey,
  });

  /// Uploads one screenshot through the platform's signed-upload pipeline and
  /// returns the media key to file with the ticket.
  ///
  /// Three steps, all real: the backend authorizes and mints a grant, the bytes
  /// go to the location that grant names (S3 in production, this API when the
  /// development disk provider is configured), and the upload is CONFIRMED —
  /// only a confirmed object may be attached.
  Future<String> uploadAttachment({
    required String token,
    required String filename,
    required String contentType,
    required Uint8List bytes,
  });

  /// One page of the signed-in shopkeeper's tickets, newest first.
  ///
  /// Paginated by the BACKEND (`limit` / `offset`). The returned page carries
  /// the server's `total` for the account, so the screen knows whether another
  /// page exists without guessing.
  Future<SupportTicketsPage> fetchTickets(
    String token, {
    int limit,
    int offset,
  });

  /// One ticket by id; fails with 404 unless it belongs to the caller.
  Future<SupportTicket> fetchTicket(int ticketId, String token);
}

class ApiSupportRepository implements SupportRepository {
  ApiSupportRepository(this._api);

  final ApiClient _api;

  @override
  Future<SupportTicket> createTicket({
    required String token,
    required IssueCategory category,
    required IssueSeverity severity,
    required String description,
    String? steps,
    String? appVersion,
    int? shopId,
    String? attachmentKey,
  }) async {
    final data =
        await _api.post(
              ApiEndpoints.supportTickets,
              token: token,
              body: {
                // Codes, not labels: the backend validates them against its own
                // taxonomy and rejects anything it cannot triage.
                'category': category.code,
                'priority': severity.code,
                'description': description,
                if (steps != null && steps.trim().isNotEmpty)
                  'steps': steps.trim(),
                if (appVersion != null && appVersion.trim().isNotEmpty)
                  'app_version': appVersion.trim(),
                'shop_id': ?shopId,
                'attachment_key': ?attachmentKey,
              },
            )
            as Map<String, dynamic>;
    return SupportTicket.fromJson(data);
  }

  @override
  Future<String> uploadAttachment({
    required String token,
    required String filename,
    required String contentType,
    required Uint8List bytes,
  }) async {
    // 1. Authorize + mint the grant. The category is pinned here, so this call
    //    can only ever produce a support-evidence object.
    final grant =
        await _api.post(
              ApiEndpoints.mediaUploadUrl,
              token: token,
              body: {
                'category': ApiEndpoints.supportAttachmentCategory,
                'filename': filename,
                'content_type': contentType,
                'size_bytes': bytes.length,
              },
            )
            as Map<String, dynamic>;

    final key = _requiredText(grant['key'], 'The upload was not authorized.');
    final part = MultipartFile.fromBytes(
      bytes,
      filename: filename,
      contentType: DioMediaType.parse(contentType),
    );

    if (_requiredText(grant['mode'], 'The upload was not authorized.') ==
        'direct') {
      // Development disk provider: the backend streams and validates the bytes.
      await _api.postMultipart(
        '${ApiEndpoints.mediaDirectUpload}'
        '?category=${ApiEndpoints.supportAttachmentCategory}',
        token: token,
        form: FormData.fromMap({'file': part}),
      );
    } else {
      // Production: multipart POST straight to the signed policy. Every field
      // the policy names must be present — including `Content-Type`, which the
      // backend's policy conditions on.
      final url = _requiredText(grant['url'], 'The upload was not authorized.');
      final fields = grant['fields'];
      if (fields is! Map) {
        throw const ApiException(message: 'The upload was not authorized.');
      }
      await _api.postFormToExternal(
        url,
        form: FormData.fromMap({
          for (final entry in fields.entries)
            entry.key.toString(): entry.value.toString(),
          'Content-Type': contentType,
          'file': part,
        }),
      );
    }

    // 2. Confirm — the backend HEADs the object, so an upload that never landed
    //    can never be attached to a ticket.
    await _api.post(
      ApiEndpoints.mediaConfirm,
      token: token,
      body: {'key': key},
    );
    return key;
  }

  @override
  Future<SupportTicketsPage> fetchTickets(
    String token, {
    int limit = supportTicketsPageSize,
    int offset = 0,
  }) async {
    final data = await _api.get(
      ApiEndpoints.supportTickets,
      token: token,
      query: {'limit': limit, 'offset': offset},
    );
    return SupportTicketsPage.fromData(data);
  }

  @override
  Future<SupportTicket> fetchTicket(int ticketId, String token) async {
    final data =
        await _api.get(
              ApiEndpoints.supportTicket(ticketId),
              token: token,
            )
            as Map<String, dynamic>;
    return SupportTicket.fromJson(data);
  }
}


/// Trimmed string, or [ApiException] when the backend sent nothing usable.
String _requiredText(Object? raw, String message) {
  final value = raw?.toString().trim() ?? '';
  if (value.isEmpty) throw ApiException(message: message);
  return value;
}

final supportRepositoryProvider = Provider<SupportRepository>(
  (ref) => ApiSupportRepository(ref.watch(apiClientProvider)),
);
