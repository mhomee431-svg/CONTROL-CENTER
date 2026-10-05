import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/widgets/network_image_view.dart';

void main() {
  /// Pumps a single widget with a known device pixel ratio so the
  /// memory-bounding maths below is deterministic.
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    double dpr = 2.0,
  }) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(devicePixelRatio: dpr),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MaterialApp(
            home: Scaffold(body: Center(child: child)),
          ),
        ),
      ),
    );
  }

  group('NetworkImageView — missing URL never crashes', () {
    testWidgets('null URL renders the missing placeholder', (tester) async {
      await pump(
        tester,
        const NetworkImageView(imageUrl: null, width: 80, height: 80),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
      // Nothing was requested, so there is no spinner to show.
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('empty string is treated as missing', (tester) async {
      await pump(
        tester,
        const NetworkImageView(imageUrl: '', width: 80, height: 80),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    });

    testWidgets('whitespace-only URL is treated as missing', (tester) async {
      await pump(
        tester,
        const NetworkImageView(imageUrl: '   ', width: 80, height: 80),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    });

    testWidgets('missing URL renders no image loader at all', (tester) async {
      // The critical guarantee: an absent URL short-circuits before any
      // network image widget is built, so no request can be attempted.
      await pump(
        tester,
        const NetworkImageView(imageUrl: '', width: 80, height: 80),
      );
      await tester.pump();

      expect(find.byType(Image), findsNothing);
    });
  });

  group('NetworkImageView — placeholder override', () {
    testWidgets('custom placeholder is used for a missing URL', (tester) async {
      await pump(
        tester,
        NetworkImageView(
          imageUrl: '',
          width: 80,
          height: 80,
          placeholder: Container(
            key: const Key('customPlaceholder'),
            color: const Color(0xFF123456),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('customPlaceholder')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('NetworkImageView — sizing and fitting', () {
    testWidgets('reserves exactly the requested box for a missing URL', (
      tester,
    ) async {
      await pump(
        tester,
        const NetworkImageView(imageUrl: '', width: 64, height: 48),
      );
      await tester.pump();

      final size = tester.getSize(find.byType(NetworkImageView));
      expect(size.width, 64);
      expect(size.height, 48);
    });

    testWidgets('absent dimensions do not throw during layout', (tester) async {
      // Infinite width/height must not be fed to the decode-bounding maths as
      // NaN or infinity.
      await pump(tester, const NetworkImageView(imageUrl: ''));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
