import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_providers.dart';
import '../domain/import_models.dart';

/// Excel inventory-import contract for one authorized shop.
///
/// The upload is a multipart POST — the shared [Dio] instance carries the
/// bearer token (backend authorization) while the file goes as `multipart/
/// form-data`, exactly like the backend `UploadFile` parameter expects.
abstract class InventoryImportRepository {
  /// Upload + server-side validate an .xlsx workbook. Returns the staged
  /// preview (row-level outcomes). Nothing has touched inventory yet.
  Future<ImportPreview> upload(
    int shopId,
    PickedWorkbook workbook,
    String token,
  );

  /// Staged-job preview (also used after upload for a fresh fetch).
  Future<ImportPreview> preview(int shopId, int jobId, String token);

  /// Confirm the staged job → process rows into the canonical inventory.
  Future<ImportConfirmResult> confirm(int shopId, int jobId, String token);

  /// One page of recent import jobs for this shop (newest first).
  ///
  /// Paginated by the BACKEND (`limit` / `offset`). The page carries the
  /// server's `total`, so Import History knows whether another page exists
  /// instead of inferring it from a short page.
  Future<ImportJobPage> listJobs(
    int shopId,
    String token, {
    int limit,
    int offset,
  });

  /// Download Sample — the import template workbook as raw .xlsx bytes.
  Future<Uint8List> downloadSample(int shopId, String token);

  /// The import schema: field vocabulary, accepted header spellings and the
  /// rules each field is validated against.
  ///
  /// Fetched once per session and cached by the controller — the vocabulary
  /// does not change between uploads, but its SOURCE must be the backend: a
  /// client that hardcodes the rules will eventually disagree with the client's
  /// own row errors.
  Future<ImportSchema> schema(String token);

  /// Submit a corrected Column Mapping and re-stage the job under it.
  ///
  /// Returns the freshly re-validated preview — the counts and row outcomes
  /// genuinely change with the mapping, so the caller must replace its preview
  /// rather than assume only the mapping moved.
  Future<ImportPreview> remap(
    int shopId,
    int jobId,
    Map<String, int?> columnMapping,
    String token,
  );
}

/// File name the sample download is offered under (kept next to the endpoint
/// so the client and the backend's Content-Disposition stay in sync).
const String sampleWorkbookFileName = 'inventory-import-sample.xlsx';

class ApiInventoryImportRepository implements InventoryImportRepository {
  ApiInventoryImportRepository(this._dio);

  final Dio _dio;

  Options _options(String token) => Options(
    headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
  );

  /// Shared error mapping for every call (envelope or Dio failure).
  Never _rethrow(DioException e) {
    final body = e.response?.data;
    if (body is Map) {
      throw ApiException(
        statusCode: e.response?.statusCode,
        errorCode: body['error_code'] as String?,
        message: (body['message'] as String?) ?? e.message ?? 'Request failed',
      );
    }
    throw ApiException.fromDioError(e);
  }

  @override
  Future<ImportPreview> upload(
    int shopId,
    PickedWorkbook workbook,
    String token,
  ) async {
    try {
      final form = FormData.fromMap(<String, dynamic>{});
      form.files.add(
        MapEntry(
          'file',
          await MultipartFile.fromFile(workbook.path, filename: workbook.name),
        ),
      );
      final response = await _dio.post(
        ApiEndpoints.inventoryImports(shopId),
        data: form,
        options: _options(token),
      );
      final body = response.data;
      if (body is Map && body['success'] == true) {
        return ImportPreview.fromJson(
          (body['data'] as Map).cast<String, dynamic>(),
        );
      }
      throw ApiException(
        statusCode: response.statusCode,
        message: body is Map
            ? (body['message'] as String? ?? 'Upload rejected')
            : 'Upload rejected',
      );
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<ImportPreview> preview(int shopId, int jobId, String token) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.inventoryImportJob(shopId, jobId),
        options: _options(token),
      );
      final body = response.data;
      if (body is Map && body['success'] == true) {
        return ImportPreview.fromJson(
          (body['data'] as Map).cast<String, dynamic>(),
        );
      }
      throw ApiException(statusCode: response.statusCode, message: 'Not found');
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<ImportConfirmResult> confirm(
    int shopId,
    int jobId,
    String token,
  ) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.inventoryImportConfirm(shopId, jobId),
        options: _options(token),
      );
      final body = response.data;
      if (body is Map && body['success'] == true) {
        return ImportConfirmResult.fromJson(
          (body['data'] as Map).cast<String, dynamic>(),
        );
      }
      throw ApiException(
        statusCode: response.statusCode,
        message: body is Map
            ? (body['message'] as String? ?? 'Confirm failed')
            : 'Confirm failed',
      );
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<ImportJobPage> listJobs(
    int shopId,
    String token, {
    int limit = importJobsPageSize,
    int offset = 0,
  }) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.inventoryImports(shopId),
        queryParameters: {'limit': limit, 'offset': offset},
        options: _options(token),
      );
      final body = response.data;
      if (body is Map && body['success'] == true) {
        final data = (body['data'] as Map).cast<String, dynamic>();
        return ImportJobPage.fromJson(data);
      }
      throw ApiException(statusCode: response.statusCode, message: 'Not found');
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<Uint8List> downloadSample(int shopId, String token) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.inventoryImportSample(shopId),
        // Raw workbook bytes — the sample is a file, not the JSON envelope.
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          responseType: ResponseType.bytes,
        ),
      );
      final bytes = response.data;
      if (bytes is Uint8List && bytes.isNotEmpty) return bytes;
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Sample could not be downloaded',
      );
    } on DioException catch (e) {
      _rethrow(e);
    }
  }
  @override
  Future<ImportSchema> schema(String token) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.inventoryImportSchema,
        options: _options(token),
      );
      final body = response.data;
      if (body is Map && body['success'] == true) {
        final data = body['data'];
        if (data is Map) {
          return ImportSchema.fromJson(data.cast<String, dynamic>());
        }
      }
      throw ApiException(statusCode: response.statusCode, message: 'No schema');
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<ImportPreview> remap(
    int shopId,
    int jobId,
    Map<String, int?> columnMapping,
    String token,
  ) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.inventoryImportRemap(shopId, jobId),
        data: {
          // Nulls are sent, not dropped: "don't import this field" is a real
          // answer and the backend clears it. Dropping the key instead would
          // leave whatever the previous mapping had.
          'column_mapping': columnMapping,
        },
        options: _options(token),
      );
      final body = response.data;
      if (body is Map && body['success'] == true) {
        return ImportPreview.fromJson(
          (body['data'] as Map).cast<String, dynamic>(),
        );
      }
      throw ApiException(
        statusCode: response.statusCode,
        message: body is Map
            ? (body['message'] as String? ?? 'Could not update the mapping')
            : 'Could not update the mapping',
      );
    } on DioException catch (e) {
      _rethrow(e);
    }
  }
}

final inventoryImportRepositoryProvider = Provider<InventoryImportRepository>((
  ref,
) {
  return ApiInventoryImportRepository(ref.watch(dioProvider));
});
