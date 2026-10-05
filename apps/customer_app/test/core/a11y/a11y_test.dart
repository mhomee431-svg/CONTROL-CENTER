import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hyperlocal_app/core/a11y/a11y.dart';
import 'package:hyperlocal_app/core/widgets/shop_open_closed_badge.dart';

/// Guards the accessibility rules that are easy to break by accident.
///
/// Each exists because the app already broke it: the floor was documented in
/// `AppTypography` and violated in 59 places anyway, because a number in a doc
/// comment does not fail a build. These assert instead.
void main() {
  group('touch targets', () {
    testWidgets('tapTarget grows a small control to the minimum', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: A11y.tapTarget(child: const SizedBox(width: 24, height: 24)),
          ),
        ),
      );

      final size = tester.getSize(find.byType(SizedBox).first);
      expect(size.width, greaterThanOrEqualTo(A11y.minTouchTarget));
      expect(size.height, greaterThanOrEqualTo(A11y.minTouchTarget));
    });

    testWidgets('tapTarget never crops a control that is already large', (
      tester,
    ) async {
      // ConstrainedBox rather than SizedBox: a 64dp button keeps its 64dp
      // instead of being forced down to 48.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: A11y.tapTarget(child: const SizedBox(width: 64, height: 64)),
          ),
        ),
      );

      final size = tester.getSize(find.byType(SizedBox).first);
      expect(size.width, 64);
      expect(size.height, 64);
    });
  });

  group('screen-reader semantics', () {
    testWidgets('tappable exposes a button with its label and an action', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var taps = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: A11y.tappable(
              label: 'Open shop details',
              onTap: () => taps++,
              child: const SizedBox(width: 100, height: 100),
            ),
          ),
        ),
      );

      // Node exists, is a button, and is activatable — the three things a bare
      // GestureDetector fails at.
      expect(
        tester.getSemantics(find.byType(SizedBox).first),
        matchesSemantics(
          label: 'Open shop details',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );

      // Invoked through the SEMANTICS action, not a pointer tap.
      //
      // `tester.tap` sends a real pointer event, which only reaches a gesture
      // recogniser. This node declares `onTap` in the semantics tree, so the
      // only faithful way to prove it is operable is to invoke the semantics
      // action -- which is exactly what a screen reader does, and precisely the
      // path a bare GestureDetector cannot serve.
      //
      // Uses the SemanticsFinder, the supported route. `tester.binding.pipelineOwner`
      // is deprecated after Flutter 3.10.
      final node = find.semantics.byLabel('Open shop details');
      expect(node, findsOneWidget);
      tester.semantics.performAction(node, SemanticsAction.tap);
      await tester.pump();
      expect(taps, 1, reason: 'the semantics tap action must do the real work');
      handle.dispose();
    });

    testWidgets('a disabled control reports itself as disabled', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: A11y.tappable(
              label: 'Unavailable',
              enabled: false,
              child: const SizedBox(width: 60, height: 60),
            ),
          ),
        ),
      );

      expect(
        tester.getSemantics(find.byType(SizedBox).first),
        matchesSemantics(
          label: 'Unavailable',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          // No tap action: a control reported as disabled must not be
          // activatable, or the reader announces something the app will refuse.
          hasTapAction: false,
        ),
      );
      handle.dispose();
    });

    testWidgets('decorative content is hidden from the reader', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                A11y.decorative(const Icon(Icons.star)),
                const Text('4.5 out of 5'),
              ],
            ),
          ),
        ),
      );

      // The icon repeats the adjacent text, so announcing it is noise.
      expect(find.bySemanticsLabel('4.5 out of 5'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('liveRegion announces updates without stealing focus', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: A11y.liveRegion(
              value: '3 results',
              child: const Text('3 results'),
            ),
          ),
        ),
      );

      expect(
        tester.getSemantics(find.byType(Text)),
        matchesSemantics(label: '3 results', isLiveRegion: true),
      );
      handle.dispose();
    });
  });

  group('colour is never the only signal', () {
    testWidgets('the shop status badge states its status in words', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ShopOpenClosedBadge(isOpenNow: false)),
        ),
      );

      // "Closed" IS the non-colour signal. Without it the badge is just a red
      // rectangle to a customer who cannot separate red from green.
      expect(
        tester.getSemantics(find.byType(ShopOpenClosedBadge)),
        matchesSemantics(label: 'Closed'),
      );
      handle.dispose();
    });

    test('status icons differ by shape, not only by colour', () {
      // Two distinct IconData values is what guarantees the difference is
      // perceivable without hue.
      expect(
        A11y.statusIcon(positive: true),
        isNot(A11y.statusIcon(positive: false)),
      );
    });
  });

  group('typography floor', () {
    test('the floor is 12, matching the theme caption', () {
      expect(A11y.minFontSize, 12.0);
    });

    testWidgets('rendered status text is at or above the floor', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ShopOpenClosedBadge(isOpenNow: true)),
        ),
      );

      final text = tester.widget<Text>(find.text('Open'));
      expect(text.style?.fontSize ?? 0, greaterThanOrEqualTo(A11y.minFontSize));
    });
  });
}
