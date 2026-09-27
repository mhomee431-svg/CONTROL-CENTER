import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../media/data/media_repository.dart';

/// Supported image formats for product images.
enum ProductImageExtension {
  jpg('jpg', 'image/jpeg'),
  jpeg('jpeg', 'image/jpeg'),
  png('png', 'image/png'),
  webp('webp', 'image/webp');

  const ProductImageExtension(this.extension, this.mimeType);

  final String extension;
  final String mimeType;

  static ProductImageExtension? fromExtension(String ext) {
    final clean = ext.toLowerCase().replaceFirst('.', '').trim();
    for (final val in ProductImageExtension.values) {
      if (val.extension == clean) return val;
    }
    return null;
  }

  static ProductImageExtension? fromMimeType(String mime) {
    final clean = mime.toLowerCase().trim();
    for (final val in ProductImageExtension.values) {
      if (val.mimeType == clean) return val;
    }
    return null;
  }
}

/// Sealed validation result for selected image files.
sealed class FileValidationResult {
  const FileValidationResult();
}

/// File passed all client-side preflight checks.
class FileValidationSuccess extends FileValidationResult {
  const FileValidationSuccess({
    required this.file,
    required this.extension,
    required this.mimeType,
    required this.sizeBytes,
  });

  final File file;
  final String extension;
  final String mimeType;
  final int sizeBytes;
}

/// File failed one of the preflight checks with a clear human-readable reason.
class FileValidationFailure extends FileValidationResult {
  const FileValidationFailure(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// Where the shopkeeper wants to pick the product image from.
enum ProductImagePickSource { camera, gallery, files }

/// Helper service for validating product image files and handling platform pickers.
class ProductImagePickerService {
  ProductImagePickerService({ImagePicker? imagePicker})
    : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  /// Maximum file size permitted for product images (5 MB).
  static const int maxBytes = MediaRepository.maxImageBytes;

  /// Allowed file extensions without leading dot.
  static const List<String> allowedExtensions = ['jpg', 'jpeg', 'png', 'webp'];

  /// Validates a local file against format, MIME type, existence, and size constraints.
  Future<FileValidationResult> validateFile(String? path) async {
    if (path == null || path.trim().isEmpty) {
      return const FileValidationFailure('No file selected');
    }

    final file = File(path);
    final exists = await file.exists();
    if (!exists) {
      return const FileValidationFailure(
        'Selected file does not exist on disk',
      );
    }

    final int size;
    try {
      size = await file.length();
    } catch (e) {
      return FileValidationFailure('Could not inspect file: $e');
    }

    if (size <= 0) {
      return const FileValidationFailure('Selected file is empty (0 bytes)');
    }

    if (size > maxBytes) {
      final mb = (maxBytes / (1024 * 1024)).toStringAsFixed(0);
      return FileValidationFailure('Image must be smaller than $mb MB');
    }

    final extStr = path.contains('.') ? path.split('.').last.toLowerCase() : '';
    final extEnum = ProductImageExtension.fromExtension(extStr);
    if (extEnum == null) {
      return FileValidationFailure(
        'Unsupported image format. Allowed: ${allowedExtensions.map((e) => e.toUpperCase()).join(", ")}',
      );
    }

    return FileValidationSuccess(
      file: file,
      extension: extEnum.extension,
      mimeType: extEnum.mimeType,
      sizeBytes: size,
    );
  }

  /// Picks an image via the given [source] (camera, gallery, or system files).
  ///
  /// Cleanly handles cancellation by returning null without throwing.
  /// Any system platform error is caught and returns null.
  Future<String?> pickImagePath(ProductImagePickSource source) async {
    try {
      switch (source) {
        case ProductImagePickSource.camera:
          final picked = await _imagePicker.pickImage(
            source: ImageSource.camera,
            maxWidth: 2000,
            imageQuality: 85,
          );
          return picked?.path;

        case ProductImagePickSource.gallery:
          final picked = await _imagePicker.pickImage(
            source: ImageSource.gallery,
            maxWidth: 2000,
            imageQuality: 85,
          );
          return picked?.path;

        case ProductImagePickSource.files:
          final result = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: allowedExtensions,
            withData: false,
          );
          return result?.files.single.path;
      }
    } catch (e) {
      debugPrint('ProductImagePickerService error: $e');
      return null;
    }
  }

  /// Convenience method that picks an image, performs thorough client-side
  /// preflight validation, and returns either [FileValidationSuccess] or [FileValidationFailure].
  ///
  /// Returns null if the user cancelled the picker.
  Future<FileValidationResult?> pickAndValidate(
    ProductImagePickSource source,
  ) async {
    final path = await pickImagePath(source);
    if (path == null) {
      // User cancelled or no path returned
      return null;
    }
    return validateFile(path);
  }
}

final productImagePickerServiceProvider = Provider<ProductImagePickerService>((
  ref,
) {
  return ProductImagePickerService();
});
