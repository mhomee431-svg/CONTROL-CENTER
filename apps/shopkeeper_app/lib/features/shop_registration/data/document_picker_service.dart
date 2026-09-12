import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/media_upload_service.dart';
import '../../shops/domain/shop_models.dart';

/// A locally-picked file ready for upload.
@immutable
class PickedFile {
  const PickedFile({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.mimeType,
  });

  final String path;
  final String name;
  final int sizeBytes;
  final String mimeType;

  String get extension =>
      name.contains('.') ? name.split('.').last.toLowerCase() : '';
}

/// Client-side pre-flight for picked files (same rules the backend enforces
/// in `MediaUploadService`). Failing fast avoids a wasted network round-trip.
class DocumentPreflight {
  DocumentPreflight._();

  /// Media category used by the secure upload API for [mediaCategory].
  static String mediaCategory(DocumentMediaCategory media) =>
      media == DocumentMediaCategory.shopImage ? 'SHOP_IMAGE' : 'DOCUMENT';

  static String? validate(PickedFile file, DocumentMediaCategory media) {
    final allowed =
        MediaUploadService.allowedExtensions[mediaCategory(media)] ??
            const <String>[];
    if (!allowed.contains(file.extension)) {
      return 'Only ${allowed.join('/')} files are supported';
    }
    if (file.sizeBytes <= 0) return 'File is empty';
    final cap = media == DocumentMediaCategory.shopImage
        ? MediaUploadService.maxImageBytes
        : MediaUploadService.maxDocumentBytes;
    if (file.sizeBytes > cap) {
      return 'File exceeds the ${cap ~/ (1024 * 1024)} MB limit';
    }
    return null;
  }

  static String mimeForExtension(String ext) => switch (ext) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        'pdf' => 'application/pdf',
        _ => 'application/octet-stream',
      };
}

/// Where the shopkeeper chose to take the file from (reference-design
/// bottom sheet: Camera / Gallery / Files).
enum PickSource { camera, gallery, files }

/// Contract for picking a verification document or photo.
abstract class DocumentPickerService {
  Future<PickedFile?> pick({
    required PickSource source,
    required DocumentMediaCategory mediaCategory,
  });
}

/// Real platform picker: camera/gallery via `image_picker`, files via
/// `file_picker`. Extension and MIME are normalised before returning.
class PlatformDocumentPicker implements DocumentPickerService {
  final ImagePicker _imagePicker = ImagePicker();

  PickedFile? _fromPath(String? path) {
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    final name = path.split(Platform.pathSeparator).last;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return PickedFile(
      path: path,
      name: name,
      sizeBytes: file.lengthSync(),
      mimeType: DocumentPreflight.mimeForExtension(ext),
    );
  }

  @override
  Future<PickedFile?> pick({
    required PickSource source,
    required DocumentMediaCategory mediaCategory,
  }) async {
    if (mediaCategory == DocumentMediaCategory.shopImage) {
      final x = await _imagePicker.pickImage(
        source: source == PickSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1920,
      );
      return _fromPath(x?.path);
    }
    if (source == PickSource.files) {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions:
            MediaUploadService.allowedExtensions['DOCUMENT'] ?? const ['pdf'],
        withData: false,
      );
      return _fromPath(result?.files.single.path);
    }
    // PDFs cannot come from the camera/gallery pickers.
    return null;
  }
}

/// Injectable so widget tests can substitute a deterministic picker.
final documentPickerProvider =
    Provider<DocumentPickerService>((ref) => PlatformDocumentPicker());
