import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/presentation/widgets/product_image_view.dart';

/// Wraps [child] in a minimal app so Theme/Semantics/Directionality resolve.
Widget host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

/// Writes [bytes] to a real temp file and returns it.
///
/// The file is created in [setUp] (outside the fake-async zone) because real
/// disk I/O awaited inside a `testWidgets` body never completes — the fake
/// clock never advances, so the real I/O callback is never delivered.
String tempFile(Directory dir, String name, List<int> bytes) {
  final file = File('${dir.path}/$name')..writeAsBytesSync(bytes);
  return file.path;
}

void main() {
  const placeholder = SizedBox(key: Key('placeholder'), width: 40, height: 40);
  const errorSlot = SizedBox(key: Key('error'), width: 40, height: 40);

  late Directory tempDir;
  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('product_image_view');
  });
  tearDown(() async {
    // Best-effort: a decoded image may still hold an open handle on Windows,
    // and a leftover temp directory must never fail an otherwise green test.
    try {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    } on FileSystemException {
      // ignored
    }
  });

  group('ProductImageView states', () {
    testWidgets('shows the placeholder when there is no image', (tester) async {
      await tester.pumpWidget(
        host(
          const ProductImageView(
            width: 40,
            height: 40,
            placeholderWidget: placeholder,
          ),
        ),
      );

      expect(find.byKey(const Key('placeholder')), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('decodes a NETWORK image at paint size, not source size', (
      tester,
    ) async {
      // §111 "unbounded image caching" / §118 memory. A catalog photo served by
      // the backend can be 2000px wide; decoding it at source resolution costs
      // tens of megabytes of bitmap for a box that paints ~120px, and the
      // decoded bitmap then sits in the image cache for the life of the screen.
      //
      // The local-file branch already falls back to [ProductImageView]'s
      // computed decode width when the caller states no `cacheWidth`. This pins
      // that the NETWORK branch does the same — otherwise the exact cost the
      // comment warns about is only avoided for files, not for the far more
      // common server-hosted case (3 of 6 call sites pass no `cacheWidth`).
      await tester.pumpWidget(
        host(
          const ProductImageView(
            width: 120,
            height: 120,
            imageUrl: 'https://cdn.hyperlocal.in/products/amul-milk.jpg',
            errorWidget: errorSlot,
          ),
        ),
      );

      final image = tester.widget<Image>(find.byType(Image));
      // `Image` wraps its provider in a ResizeImage when a decode size is set,
      // so an unwrapped NetworkImage means "decoded at full resolution".
      expect(
        image.image,
        isA<ResizeImage>(),
        reason: 'a network image must be decoded at paint size, not source size',
      );
      final resized = image.image as ResizeImage;
      expect(
        resized.width,
        isNotNull,
        reason: 'a bounded decode width must reach the image cache',
      );
      expect(resized.width, lessThanOrEqualTo(1024));
      // A 120dp box at the binding's device pixel ratio — never the source
      // resolution. Computed rather than hardcoded because the test binding
      // reports DPR 3.0, so a literal here would encode that detail.
      final dpr = tester.view.devicePixelRatio;
      expect(resized.width, (120 * dpr).ceil());
    });

    testWidgets('keeps the old frame while a ROTATED presigned URL reloads', (
      tester,
    ) async {
      // The backend serves product images as PRESIGNED URLs, so the URL string
      // changes on every refresh even though the picture is the same. Flutter
      // treats a changed provider as a brand-new image, so without
      // `gaplessPlayback` every pull-to-refresh drops the decoded frame and
      // flashes the loading placeholder across every thumbnail in the product
      // list — visible flicker on the app's main scrolling screen.
      //
      // (The same applies when a shopkeeper replaces a local photo: the path
      // changes and the preview would blank out.)
      await tester.pumpWidget(
        host(
          const ProductImageView(
            width: 48,
            height: 48,
            imageUrl:
                'https://cdn.hyperlocal.in/products/amul-milk.jpg'
                '?X-Amz-Signature=abc123&X-Amz-Expires=900',
            errorWidget: errorSlot,
          ),
        ),
      );

      final image = tester.widget<Image>(find.byType(Image));
      expect(
        image.gaplessPlayback,
        isTrue,
        reason: 'a rotated URL must not blank an already-decoded thumbnail',
      );
    });

    testWidgets('treats a blank url as "no image", not a failed load', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const ProductImageView(
            imageUrl: '   ',
            width: 40,
            height: 40,
            placeholderWidget: placeholder,
          ),
        ),
      );

      expect(find.byKey(const Key('placeholder')), findsOneWidget);
    });

    testWidgets(
      'falls back for a malformed (non-http) url without a network call',
      (tester) async {
        await tester.pumpWidget(
          host(
            const ProductImageView(
              imageUrl: 'not a url',
              width: 40,
              height: 40,
              errorWidget: errorSlot,
            ),
          ),
        );

        expect(find.byKey(const Key('error')), findsOneWidget);
        expect(find.byType(Image), findsNothing);
      },
    );

    testWidgets('renders a real local file', (tester) async {
      // A 1x1 transparent PNG.
      final path = tempFile(
        tempDir,
        'p.png',
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
          'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
        ),
      );

      await tester.pumpWidget(
        host(ProductImageView(localPath: path, width: 40, height: 40)),
      );
      await tester.pump();

      // The `Image` widget is in the tree as soon as it is built; the decode
      // result arrives later and does not remove it, so no real I/O is awaited.
      expect(find.byType(Image), findsOneWidget);
    });

    // NOTE: there is deliberately no "undecodable local file" case here.
    // `Image.file` only reports a decode failure through a real codec run, and
    // `flutter_test`'s test codec resolves every image synchronously without
    // ever signalling an error — so such a test would assert on fake-codec
    // timing rather than on our behaviour. The `errorWidget` branch is covered
    // deterministically by the malformed-URL case above.
  });

  group('ProductImageView edit actions', () {
    testWidgets('replace is offered only while editable', (tester) async {
      var replaced = 0;

      await tester.pumpWidget(
        host(
          ProductImageView(
            width: 40,
            height: 40,
            isEditable: true,
            onReplace: () => replaced++,
            onRemove: () {},
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.edit_outlined));
      expect(replaced, 1);

      await tester.pumpWidget(
        host(
          ProductImageView(
            width: 40,
            height: 40,
            isEditable: false,
            onReplace: () => replaced++,
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.edit_outlined), findsNothing);
    });

    testWidgets('remove is hidden while there is no photo to detach', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          ProductImageView(
            width: 40,
            height: 40,
            isEditable: true,
            onReplace: () {},
            onRemove: () {},
            placeholderWidget: placeholder,
          ),
        ),
      );

      // Nothing stored, nothing to remove — offering "remove" would be a lie.
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    });

    testWidgets('remove fires for a product that already has a photo', (
      tester,
    ) async {
      var removed = 0;
      final path = tempFile(tempDir, 'p.png', [1, 2, 3]);

      await tester.pumpWidget(
        host(
          ProductImageView(
            localPath: path,
            width: 40,
            height: 40,
            isEditable: true,
            onReplace: () {},
            onRemove: () => removed++,
            errorWidget: errorSlot,
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.delete_outline));
      expect(removed, 1);
    });
  });
}
