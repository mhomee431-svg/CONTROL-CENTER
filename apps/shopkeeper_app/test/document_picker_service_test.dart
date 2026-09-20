import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/features/shop_registration/data/document_picker_service.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/domain/shop_models.dart';

void main() {
  group('DocumentPreflight.allowedFor — mirrors the upload API', () {
    test('image slots accept photo formats but never PDF', () {
      final allowed =
          DocumentPreflight.allowedFor(DocumentMediaCategory.shopImage);
      expect(allowed, containsAll(<String>['jpg', 'jpeg', 'png', 'webp']));
      expect(allowed, isNot(contains('pdf')));
    });

    test('document slots accept only PDF', () {
      expect(
        DocumentPreflight.allowedFor(DocumentMediaCategory.document),
        ['pdf'],
      );
    });
  });

  group('DocumentPreflight.fromPlatform', () {
    PickedFile? from(String? path, String name, int size) =>
        DocumentPreflight.fromPlatform(path: path, name: name, sizeBytes: size);

    test('maps extensions to the mime types the upload API expects', () {
      final pdf = from('/tmp/gst.pdf', 'gst.pdf', 100);
      expect(pdf, isNotNull);
      expect(pdf!.mimeType, 'application/pdf');
      expect(pdf.extension, 'pdf');

      expect(from('/tmp/a.jpg', 'a.jpg', 10)!.mimeType, 'image/jpeg');
      expect(from('/tmp/a.PNG', 'a.PNG', 10)!.extension, 'png');
      expect(from('/tmp/a.webp', 'a.webp', 10)!.mimeType, 'image/webp');
    });

    test('extensionless names fall back to the generic mime type', () {
      final file = from('/tmp/scan', 'scan', 10);
      expect(file, isNotNull);
      expect(file!.extension, '');
      expect(file.mimeType, 'application/octet-stream');
    });

    test('cancelled or path-less selections yield null', () {
      expect(from(null, 'a.pdf', 10), isNull);
      expect(from('', 'a.pdf', 10), isNull);
      expect(from('/tmp/', '   ', 10), isNull);
    });
  });

  group('PlatformDocumentPicker guards', () {
    final picker = PlatformDocumentPicker();

    test('camera/gallery are refused for PDF-only slots before any plugin call',
        () async {
      // Must not reach the camera: document slots only accept PDF.
      expect(
        await picker.pick(
          source: PickSource.camera,
          mediaCategory: DocumentMediaCategory.document,
        ),
        isNull,
      );
      expect(
        await picker.pick(
          source: PickSource.gallery,
          mediaCategory: DocumentMediaCategory.document,
        ),
        isNull,
      );
    });
  });

  group('DocumentPreflight.validate — last line before the network', () {
    PickedFile file(String name, int sizeBytes) => PickedFile(
          path: '/tmp/$name',
          name: name,
          sizeBytes: sizeBytes,
          mimeType: DocumentPreflight.mimeForExtension(
            name.split('.').last.toLowerCase(),
          ),
        );

    test('accepts a PDF for a document slot', () {
      expect(
        DocumentPreflight.validate(
            file('gst.pdf', 1024), DocumentMediaCategory.document),
        isNull,
      );
    });

    test('accepts a photo for an image slot', () {
      expect(
        DocumentPreflight.validate(
            file('shop.png', 1024), DocumentMediaCategory.shopImage),
        isNull,
      );
    });

    test('rejects a non-PDF for a document slot', () {
      final error = DocumentPreflight.validate(
          file('gst.exe', 1024), DocumentMediaCategory.document);
      expect(error, isNotNull);
      expect(error, contains('pdf'));
    });

    test('rejects a file larger than the category cap', () {
      final error = DocumentPreflight.validate(
          file('shop.jpg', 5 * 1024 * 1024 + 1), DocumentMediaCategory.shopImage);
      expect(error, isNotNull);
      expect(error, contains('5 MB'));
    });

    test('rejects an empty file', () {
      expect(
        DocumentPreflight.validate(
            file('gst.pdf', 0), DocumentMediaCategory.document),
        'File is empty',
      );
    });
  });
}

