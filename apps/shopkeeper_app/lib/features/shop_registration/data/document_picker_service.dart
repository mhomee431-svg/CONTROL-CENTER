
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
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

  /// Extensions the secure upload API accepts for [media] (lower-case, no dot).
  /// The pickers are filtered with this list so a shopkeeper can never select a
  /// file the backend would reject.
  static List<String> allowedFor(DocumentMediaCategory media) =>
      MediaUploadService.allowedExtensions[mediaCategory(media)] ??
          const <String>[];

  /// Builds a [PickedFile] from platform-provided data.
  ///
  /// Returns null when the platform reported no usable file — the user
  /// cancelled, or the platform gave no path (e.g. web) — so "cancelled" and
  /// "unsupported" both simply leave the slot empty.
  static PickedFile? fromPlatform({
    required String? path,
    required String name,
    required int sizeBytes,
  }) {
    if (path == null || path.isEmpty || name.trim().isEmpty) return null;
    final extension =
        name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return PickedFile(
      path: path,
      name: name,
      sizeBytes: sizeBytes,
      mimeType: mimeForExtension(extension),
    );
  }
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

/// Real platform picker — camera and gallery through `image_picker` (photos)
/// and the system file browser through `file_picker` (PDF). Every result is
/// filtered by the extensions the secure upload API accepts for the slot's
/// media category, so a shopkeeper can never select a file the backend would
/// reject.
class PlatformDocumentPicker implements DocumentPickerService {
  PlatformDocumentPicker({ImagePicker? imagePicker})
      : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  @override
  Future<PickedFile?> pick({
    required PickSource source,
    required DocumentMediaCategory mediaCategory,
  }) async {
    // PDF slots go straight to the file browser; camera/gallery produce
    // photos, so they are only meaningful for image slots.
    if (source == PickSource.files) return _pickFile(mediaCategory);
    final acceptsImages =
        DocumentPreflight.allowedFor(mediaCategory).any((e) => e != 'pdf');
    if (!acceptsImages) return null;

    XFile? photo;
    try {
      photo = await _imagePicker.pickImage(
        source: source == PickSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        // Re-encode downscaled so a 12 MP photo stays inside the backend's
        // 5 MB image cap.
        maxWidth: 2000,
        imageQuality: 85,
      );
    } on PlatformException catch (e) {
      debugPrint('DocumentPicker: image_picker failed (${e.code})');
      return null;
    }
    if (photo == null) return null;
    return DocumentPreflight.fromPlatform(
      path: photo.path,
      name: photo.name,
      sizeBytes: await _sizeOf(photo.path),
    );
  }

  Future<PickedFile?> _pickFile(DocumentMediaCategory mediaCategory) async {
    final allowed = DocumentPreflight.allowedFor(mediaCategory);
    if (allowed.isEmpty) return null;
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowed,
        withData: false,
      );
    } on PlatformException catch (e) {
      debugPrint('DocumentPicker: file_picker failed (${e.code})');
      return null;
    }
    final platformFile = result?.files.single;
    if (platformFile == null) return null;
    return DocumentPreflight.fromPlatform(
      path: platformFile.path,
      name: platformFile.name,
      sizeBytes: platformFile.size,
    );
  }

  /// Size via the file system — works for both the camera cache and gallery
  /// copies; returns 0 when the platform cannot stat the file (the pre-flight
  /// then reports it as empty rather than sending a broken upload).
  Future<int> _sizeOf(String path) async {
    try {
      return await File(path).length();
    } catch (_) {
      return 0;
    }
  }
}

/// Injectable so widget tests can substitute a deterministic picker.
final documentPickerProvider =
    Provider<DocumentPickerService>((ref) => PlatformDocumentPicker());
