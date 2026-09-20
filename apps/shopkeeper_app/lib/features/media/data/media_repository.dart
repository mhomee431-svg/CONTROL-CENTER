import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/media_upload_service.dart';
import '../../../core/network/token_store.dart';

/// Re-exported so feature code can name [MediaObject] while depending only
/// on this repository (never on the raw network service).
export '../../../core/network/media_upload_service.dart' show MediaObject;

/// Media data access for one authorized shopkeeper.
///
/// Ownership (repository rule): everything that moves BINARY objects to and
/// from the platform's object store lives here — S3 uploads (image/product and
/// verification-document categories), confirm + short-lived read URLs, and
/// authorized deletes. It never reads or mutates app data; callers attach the
/// confirmed `key` to their own domain entities (products via
/// [ProductRepository], documents via [ShopRepository]).
///
/// Authentication is owned HERE: the token is resolved from the token store
/// on every call, so presentation code and controllers never touch raw
/// credentials. `MediaUploadService` stays the underlying network mechanics
/// (signed-policy flow) and is not consumed outside this file.
abstract class MediaRepository {
  /// Client-side pre-flight limits, mirrored from [MediaUploadService] (the
  /// single source of truth). Pickers and forms use these for fast, friendly
  /// failure before any network round trip.
  static const Map<String, List<String>> allowedExtensions =
      MediaUploadService.allowedExtensions;
  static const int maxImageBytes = MediaUploadService.maxImageBytes;
  static const int maxDocumentBytes = MediaUploadService.maxDocumentBytes;

  /// Upload a local file under [category] and return the confirmed object
  /// (server-minted key + short-lived read URL). Throws [ApiException] on
  /// any failure (including "not signed in").
  Future<MediaObject> upload({
    required String category,
    required String filePath,
    required String contentType,
    int? shopId,
  });

  /// Verify a completed upload and get a short-lived read URL.
  Future<MediaObject> confirm({required String key});

  /// Authorized short-lived read URL for an object the caller may access.
  Future<MediaObject> readUrl({required String key});

  /// Delete an object (owner/manager/admin per backend access control).
  Future<void> delete({required String key});
}

class ApiMediaRepository implements MediaRepository {
  ApiMediaRepository(this._service, this._tokens);

  final MediaUploadService _service;
  final TokenStore _tokens;

  /// Resolves the access token, or fails the same way callers used to fail
  /// when they handled credentials themselves.
  Future<String?> _token() => _tokens.readAccessToken();

  @override
  Future<MediaObject> upload({
    required String category,
    required String filePath,
    required String contentType,
    int? shopId,
  }) async {
    final token = await _token();
    if (token == null) throw const ApiException(message: 'Not signed in');
    return _service.upload(
      token: token,
      category: category,
      filePath: filePath,
      contentType: contentType,
      shopId: shopId,
    );
  }

  @override
  Future<MediaObject> confirm({required String key}) async {
    final token = await _token();
    if (token == null) throw const ApiException(message: 'Not signed in');
    return _service.confirm(token: token, key: key);
  }

  @override
  Future<MediaObject> readUrl({required String key}) async {
    final token = await _token();
    if (token == null) throw const ApiException(message: 'Not signed in');
    return _service.readUrl(token: token, key: key);
  }

  @override
  Future<void> delete({required String key}) async {
    final token = await _token();
    if (token == null) throw const ApiException(message: 'Not signed in');
    return _service.delete(token: token, key: key);
  }
}

final mediaRepositoryProvider = Provider<MediaRepository>((ref) {
  return ApiMediaRepository(
    ref.watch(mediaUploadServiceProvider),
    ref.watch(tokenStoreProvider),
  );
});
