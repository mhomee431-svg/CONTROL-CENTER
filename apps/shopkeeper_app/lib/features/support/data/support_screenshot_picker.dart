import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// One picked screenshot, ready to upload.
@immutable
class PickedScreenshot {
  const PickedScreenshot({
    required this.filename,
    required this.contentType,
    required this.bytes,
  });

  /// Name to upload under; always ends with the extension of [contentType].
  final String filename;

  /// One of the image types the backend accepts for support evidence.
  final String contentType;

  final Uint8List bytes;

  int get sizeBytes => bytes.length;

  @override
  bool operator ==(Object other) =>
      other is PickedScreenshot &&
      other.filename == filename &&
      other.contentType == contentType &&
      listEquals(other.bytes, bytes);

  @override
  int get hashCode => Object.hash(filename, contentType, Object.hashAll(bytes));
}

/// Where the screenshot comes from.
enum ScreenshotSource {
  /// Shoot the screen / the device with the camera.
  camera,

  /// Pick an existing image (a saved screenshot).
  gallery,
}

/// Picks ONE screenshot to attach to a support report.
///
/// An interface rather than a direct `image_picker` call so the report screen
/// can be exercised in tests without a platform channel — the platform
/// implementation is the only place that touches the plugin.
abstract class SupportScreenshotPicker {
  /// The chosen image, or null when the shopkeeper cancelled.
  Future<PickedScreenshot?> pick(ScreenshotSource source);
}

/// The real picker: camera or gallery through `image_picker`.
class PlatformSupportScreenshotPicker implements SupportScreenshotPicker {
  const PlatformSupportScreenshotPicker();

  /// Largest dimension either axis may have in the uploaded evidence. The
  /// backend enforces a hard cap for this media category; downsampling to this
  /// size keeps even a 12 MP frame comfortably inside it.
  static const double maxDimension = 2000;

  /// JPEG/WEBP quality for the first compression pass. Lower passes are tried
  /// automatically if the result is still over [maxBytes].
  static const int quality = 85;

  /// Hard payload cap on the compressed evidence: 2 MB. Stricter than the
  /// backend category cap so the signed S3 content-length-range policy the
  /// backend mints can never reject the upload on size.
  static const int maxBytes = 2 * 1024 * 1024; // 2 MB

  @override
  Future<PickedScreenshot?> pick(ScreenshotSource source) async {
    final file = await ImagePicker().pickImage(
      source: source == ScreenshotSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
    );
    if (file == null) return null; // cancelled — nothing to attach

    final original = await file.readAsBytes();
    // image_picker can hand back HEIC (iOS) or other containers the backend
    // does not accept. Validate the magic number before spending work encoding
    // — the TYPE is sniffed from the bytes, never taken from the filename,
    // because the backend re-checks the stored object on confirm and a declared
    // type that disagrees with the content would fail later and less clearly.
    if (sniffImageContentType(original) == null) return null;

    // Encode to WebP and step quality down until the payload fits under
    // [maxBytes]. WebP is the only format this flow emits (jpeg/png/webp are
    // all the backend accepts, and WebP is smallest), and the 2 MB cap is
    // enforced here so the S3 content-length-range condition the backend
    // minted can never reject the upload on size.
    final bytes = await _compressToWebP(original);
    return PickedScreenshot(
      filename: nameForContentType(file.name, 'image/webp'),
      contentType: 'image/webp',
      bytes: bytes,
    );
  }

  /// Encodes [bytes] as WebP, stepping [quality] down until the payload fits in
  /// [maxBytes]. Always returns a WebP payload — the most aggressive encoding
  /// that stayed under the cap, or the smallest one tried as a last resort.
  static Future<Uint8List> _compressToWebP(Uint8List bytes) async {
    Uint8List? smallest;
    for (final q in [quality, 75, 60, 45, 30, 15, 8]) {
      final out = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: maxDimension.toInt(),
        minHeight: maxDimension.toInt(),
        quality: q,
        format: CompressFormat.webp,
        autoCorrectionAngle: true,
      );
      if (out.length <= maxBytes) return out;
      if (smallest == null || out.length < smallest.length) smallest = out;
    }
    return smallest ?? bytes;
  }

  /// Content type of [bytes] from its magic number, or null when it is not one
  /// of the types the backend accepts for support evidence (JPEG/PNG/WebP).
  static String? sniffImageContentType(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 && // R
        bytes[1] == 0x49 && // I
        bytes[2] == 0x46 && // F
        bytes[3] == 0x46 && // F
        bytes[8] == 0x57 && // W
        bytes[9] == 0x45 && // E
        bytes[10] == 0x42 && // B
        bytes[11] == 0x50) {
      // P
      return 'image/webp';
    }
    return null;
  }

  /// [original] with an extension matching [contentType].
  ///
  /// The backend derives the allowed extension FROM the declared content type,
  /// so a name that keeps a mismatched suffix (a `.jpeg` name for PNG bytes)
  /// would be rejected as an unsupported file.
  static String nameForContentType(String original, String contentType) {
    final extension = switch (contentType) {
      'image/png' => '.png',
      'image/webp' => '.webp',
      _ => '.jpg',
    };
    final name = original.trim();
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final safeBase = base.trim().isEmpty ? 'screenshot' : base.trim();
    return '$safeBase$extension';
  }
}

final supportScreenshotPickerProvider = Provider<SupportScreenshotPicker>(
  (ref) => const PlatformSupportScreenshotPicker(),
);
