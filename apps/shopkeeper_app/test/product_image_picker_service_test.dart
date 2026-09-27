import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_image_picker_service.dart';

void main() {
  group('ProductImageExtension', () {
    test('maps every accepted extension to the mime type the API expects', () {
      expect(
        ProductImageExtension.fromExtension('jpg')?.mimeType,
        'image/jpeg',
      );
      expect(
        ProductImageExtension.fromExtension('JPEG')?.mimeType,
        'image/jpeg',
      );
      expect(
        ProductImageExtension.fromExtension('.png')?.mimeType,
        'image/png',
      );
      expect(
        ProductImageExtension.fromExtension('webp')?.mimeType,
        'image/webp',
      );
    });

    test('rejects formats the backend does not accept', () {
      // HEIC/BMP/GIF slip through the platform's own image filter, so the
      // client preflight has to name them as unsupported.
      for (final ext in ['heic', 'bmp', 'gif', 'pdf', 'txt', 'exe']) {
        expect(
          ProductImageExtension.fromExtension(ext),
          isNull,
          reason: '$ext must not be accepted',
        );
      }
    });

    test('round-trips through the mime type', () {
      expect(ProductImageExtension.fromMimeType('image/PNG')?.extension, 'png');
      expect(
        ProductImageExtension.fromMimeType('image/jpeg')?.extension,
        'jpg',
      );
      expect(ProductImageExtension.fromMimeType('application/pdf'), isNull);
    });
  });

  group('ProductImagePickerService.validateFile', () {
    late Directory dir;
    final service = ProductImagePickerService();

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('product_image_test');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    File write(String name, int bytes) {
      final f = File('${dir.path}${Platform.pathSeparator}$name');
      f.writeAsBytesSync(List<int>.filled(bytes, 1));
      return f;
    }

    String reason(FileValidationResult result) =>
        (result as FileValidationFailure).reason;

    test('accepts a small jpg and reports its mime type', () async {
      final result = await service.validateFile(write('a.jpg', 128).path);
      expect(result, isA<FileValidationSuccess>());
      final ok = result as FileValidationSuccess;
      expect(ok.mimeType, 'image/jpeg');
      expect(ok.extension, 'jpg');
      expect(ok.sizeBytes, 128);
    });

    test('accepts png and webp', () async {
      expect(
        (await service.validateFile(
          write('a.png', 64).path,
        ) as FileValidationSuccess).mimeType,
        'image/png',
      );
      expect(
        (await service.validateFile(
          write('a.webp', 64).path,
        ) as FileValidationSuccess).mimeType,
        'image/webp',
      );
    });

    test('accepts a file exactly at the 5 MB limit', () async {
      final result = await service.validateFile(
        write('big.png', ProductImagePickerService.maxBytes).path,
      );
      expect(result, isA<FileValidationSuccess>());
    });

    test(
      'rejects an unsupported extension and names the allowed ones',
      () async {
        final result = await service.validateFile(write('doc.pdf', 64).path);
        expect(result, isA<FileValidationFailure>());
        expect(reason(result), contains('Unsupported image format'));
        expect(reason(result), contains('JPG'));
      },
    );

    test('rejects an oversized file with the readable limit', () async {
      final result = await service.validateFile(
        write('huge.jpg', ProductImagePickerService.maxBytes + 1).path,
      );
      expect(result, isA<FileValidationFailure>());
      expect(reason(result), contains('5 MB'));
    });

    test(
      'rejects an empty file rather than uploading a zero-byte body',
      () async {
        final result = await service.validateFile(write('empty.png', 0).path);
        expect(result, isA<FileValidationFailure>());
        expect(reason(result), contains('0 bytes'));
      },
    );

    test('rejects a path that no longer exists on disk', () async {
      final ghost = '${dir.path}${Platform.pathSeparator}gone.jpg';
      final result = await service.validateFile(ghost);
      expect(result, isA<FileValidationFailure>());
      expect(reason(result), contains('does not exist'));
    });

    test('treats null/blank paths as a no-op, not an error', () async {
      expect(reason(await service.validateFile(null)), 'No file selected');
      expect(reason(await service.validateFile('   ')), 'No file selected');
    });
  });
}
