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

  /// Recent import jobs for this shop (newest first).
  Future<List<ImportJob>> listJobs(int shopId, String token, {int limit});

  /// Download Sample — the import template workbook as raw .xlsx bytes.
  Future<Uint8List> downloadSample(int shopId, String token);
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
  Future<List<ImportJob>> listJobs(
    int shopId,
    String token, {
    int limit = 20,
  }) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.inventoryImports(shopId),
        queryParameters: {'limit': limit},
        options: _options(token),
      );
      final body = response.data;
      if (body is Map && body['success'] == true) {
        final data = (body['data'] as Map).cast<String, dynamic>();
        return ((data['items'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ImportJob.fromJson)
            .toList(growable: false);
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
}

final inventoryImportRepositoryProvider = Provider<InventoryImportRepository>((
  ref,
) {
  return ApiInventoryImportRepository(ref.watch(dioProvider));
});
