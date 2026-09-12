import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'api_endpoints.dart';
import 'api_providers.dart';

/// Phase 7 — client side of the secure S3 upload flow.
///
///     Flutter → backend authorization → signed upload policy → S3
///
/// AWS credentials never reach the client. The backend authorizes the caller,
/// validates the declared file, mints the object key, and returns a
/// short-lived presigned POST policy whose conditions pin the exact key,
/// content type, and size cap. The file is uploaded directly to S3, then
/// [confirm] makes the backend HEAD-verify the stored object and return a
/// short-lived read URL.
class MediaUploadService {
  MediaUploadService({required this.apiClient, required this.dio});

  /// Authenticated client for backend calls (token attached by caller).
  final ApiClient apiClient;

  /// Bare Dio instance used ONLY for the direct-to-S3 multipart POST.
  /// Must carry no auth headers / interceptors — credentials must never be
  /// sent to the object store.
  final Dio dio;

  /// Client-side pre-flight checks (fail fast, before any network round trip).
  /// The backend enforces the same rules — this is UX, not security.
  static const Map<String, List<String>> allowedExtensions = {
    'PRODUCT_IMAGE': ['jpg', 'jpeg', 'png', 'webp'],
    'SHOP_IMAGE': ['jpg', 'jpeg', 'png', 'webp'],
    'DOCUMENT': ['pdf'],
  };
  static const int maxImageBytes = 5 * 1024 * 1024; // 5 MB
  static const int maxDocumentBytes = 15 * 1024 * 1024; // 15 MB

  /// Upload a local file under [category] and return the confirmed object
  /// (key + short-lived read URL). Throws [ApiException] on any failure.
  Future<MediaObject> upload({
    required String token,
    required String category,
    required String filePath,
    required String contentType,
    int? shopId,
  }) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw ApiException(message: 'File not found: $filePath');
    }
    final size = file.lengthSync();
    final name = filePath.split(Platform.pathSeparator).last;
    _preflight(category, name, size);

    // 1) Backend authorization + validation + signed policy.
    final grant = await apiClient.post(
      ApiEndpoints.mediaUploadUrl,
      token: token,
      body: {
        'category': category,
        'filename': name,
        'content_type': contentType,
        'size_bytes': size,
        'shop_id': ?shopId,
      },
    ) as Map<String, dynamic>;

    final mode = grant['mode'] as String?;
    if (mode != 'post') {
      // Local-dev backend may offer direct mode; not supported in prod flow.
      throw ApiException(
        message: 'Signed upload unavailable (mode: $mode)',
        errorCode: 'SIGNED_UPLOAD_REQUIRED',
      );
    }

    // 2) Direct-to-S3 multipart POST with the presigned policy fields.
    final fields = (grant['fields'] as Map).cast<String, String>();
    final form = FormData();
    fields.forEach((k, v) => form.fields.add(MapEntry(k, v)));
    form.files.add(
      MapEntry(
        'file',
        await MultipartFile.fromFile(
          filePath,
          contentType: DioMediaType.parse(contentType),
        ),
      ),
    );
    try {
      final s3Response = await dio.post<void>(
        grant['url'] as String,
        data: form,
        options: Options(contentType: 'multipart/form-data'),
      );
      final code = s3Response.statusCode;
      if (code != null && code >= 300) {
        throw ApiException(
          statusCode: code,
          errorCode: 'S3_UPLOAD_FAILED',
          message: 'Object store rejected the upload',
        );
      }
    } on DioException catch (e) {
      throw ApiException(
        statusCode: e.response?.statusCode,
        errorCode: 'S3_UPLOAD_FAILED',
        message: 'Upload to object store failed: ${e.message ?? e.type.name}',
      );
    }

    // 3) Confirm — backend HEADs the object and returns a read URL.
    return confirm(token: token, key: grant['key'] as String);
  }

  /// Verify a completed upload and get a short-lived read URL.
  Future<MediaObject> confirm({required String token, required String key}) async {
    final data = await apiClient.post(
      ApiEndpoints.mediaConfirm,
      token: token,
      body: {'key': key},
    ) as Map<String, dynamic>;
    return MediaObject.fromJson(data);
  }

  /// Authorized short-lived read URL for an object the caller may access.
  Future<MediaObject> readUrl({required String token, required String key}) async {
    final data = await apiClient.get(
      ApiEndpoints.mediaUrl,
      token: token,
      query: {'key': key},
    ) as Map<String, dynamic>;
    return MediaObject.fromJson(data);
  }

  /// Delete an object (owner/manager/admin per backend access control).
  Future<void> delete({required String token, required String key}) async {
    await apiClient.delete(
      '${ApiEndpoints.mediaObjects}?key=$key',
      token: token,
    );
  }

  void _preflight(String category, String filename, int sizeBytes) {
    final ext =
        filename.contains('.') ? filename.split('.').last.toLowerCase() : '';
    final allowed = allowedExtensions[category];
    if (allowed == null) {
      throw ApiException(message: 'Unknown media category: $category');
    }
    if (!allowed.contains(ext)) {
      throw ApiException(
        errorCode: 'INVALID_FILE_TYPE',
        message: 'Only ${allowed.join('/')} files are supported',
      );
    }
    final cap = category == 'DOCUMENT' ? maxDocumentBytes : maxImageBytes;
    if (sizeBytes > cap) {
      throw ApiException(
        errorCode: 'FILE_TOO_LARGE',
        message: 'File exceeds the ${cap ~/ (1024 * 1024)} MB limit',
      );
    }
    if (sizeBytes <= 0) {
      throw ApiException(
        errorCode: 'EMPTY_FILE',
        message: 'File is empty',
      );
    }
  }
}

/// A confirmed media object: its server-minted key and a short-lived URL.
class MediaObject {
  const MediaObject({
    required this.key,
    required this.url,
    this.category,
    this.size,
    this.contentType,
  });

  final String key;
  final String url;
  final String? category;
  final int? size;
  final String? contentType;

  factory MediaObject.fromJson(Map<String, dynamic> json) => MediaObject(
        key: json['key'] as String,
        url: json['url'] as String? ?? '',
        category: json['category'] as String?,
        size: json['size'] as int?,
        contentType: json['content_type'] as String?,
      );
}

/// Injectable service wired to the shared network layer. The S3 `dio` here is
/// a bare instance (no auth headers) exactly as [MediaUploadService] requires.
final mediaUploadServiceProvider = Provider<MediaUploadService>((ref) {
  return MediaUploadService(
    apiClient: ref.watch(apiClientProvider),
    dio: Dio(),
  );
});