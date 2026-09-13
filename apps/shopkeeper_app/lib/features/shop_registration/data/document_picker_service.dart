import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Stub platform picker for MVP — file_picker/image_picker disabled.
/// Returns null; re-enable by uncommenting the packages in pubspec.yaml
/// and restoring the real implementation.
class PlatformDocumentPicker implements DocumentPickerService {
  const PlatformDocumentPicker();

  @override
  Future<PickedFile?> pick({
    required PickSource source,
    required DocumentMediaCategory mediaCategory,
  }) async {
    // MVP: document picking disabled (requires compileSdk 36 plugin fixes)
    debugPrint('DocumentPicker: picking disabled for MVP '
        '(source=$source, category=$mediaCategory)');
    return null;
  }
}

/// Injectable so widget tests can substitute a deterministic picker.
final documentPickerProvider =
    Provider<DocumentPickerService>((ref) => const PlatformDocumentPicker());
