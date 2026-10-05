import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/widgets/skeletons.dart';
import 'package:hyperlocal_app/core/widgets/slow_load_notice.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('SlowLoadNotice', () {
    testWidgets('says nothing at all during a normal, fast load', (
      tester,
    ) async {
      // A notice that appeared immediately would turn every quick load into an
      // apology. This is a footnote to a slow load, not a second loading state.
      await tester.pumpWidget(
        _host(
          const SlowLoadNotice(
            after: Duration(seconds: 8),
            message: 'This is taking longer than usual.',
          ),
        ),
      );

      expect(find.text('This is taking longer than usual.'), findsNothing);

      // Still nothing just before the threshold.
      await tester.pump(const Duration(seconds: 7));
      expect(find.text('This is taking longer than usual.'), findsNothing);
    });

    testWidgets('explains the wait once it passes the threshold', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const SlowLoadNotice(
            after: Duration(seconds: 8),
            message: 'This is taking longer than usual.',
          ),
        ),
      );

      await tester.pump(const Duration(seconds: 8));
      await tester.pump();
      expect(find.text('This is taking longer than usual.'), findsOneWidget);
    });

    testWidgets('offers a retry only when one is actually possible', (
      tester,
    ) async {
      var retries = 0;

      await tester.pumpWidget(
        _host(
          SlowLoadNotice(
            after: const Duration(seconds: 1),
            message: 'Still working.',
            onRetry: () => retries++,
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      await tester.tap(find.byKey(const Key('slowLoadRetry')));
      await tester.pump();
      expect(retries, 1);
    });

    testWidgets('renders no button when the caller has no retry to offer', (
      tester,
    ) async {
      // A Retry that cannot re-issue anything is a dead control, which the
      // error-handling rules forbid — so the slot being null hides the button.
      await tester.pumpWidget(
        _host(
          const SlowLoadNotice(
            after: Duration(seconds: 1),
            message: 'The map is taking longer to load.',
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.text('The map is taking longer to load.'), findsOneWidget);
      expect(find.byKey(const Key('slowLoadRetry')), findsNothing);
    });

    testWidgets('leaves no pending timer behind when it is disposed', (
      tester,
    ) async {
      // Regression guard. A live timer surviving a route pop makes the whole
      // suite fail with "A Timer is still pending after the widget tree was
      // disposed", and the cancel belongs in the widget, not in every test.
      await tester.pumpWidget(
        _host(
          const SlowLoadNotice(
            after: Duration(seconds: 30),
            message: 'never shown',
          ),
        ),
      );

      // Tear the tree down BEFORE the timer could ever fire.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      // Reaching the end of the test without a pending-timer failure is the
      // assertion; nothing further is needed here.
    });
  });

  group('skeletons', () {
    testWidgets('draw the shape of the content without claiming any of it', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const SkeletonList(itemCount: 3, rowHeight: 96)),
      );

      expect(find.byType(SkeletonCardRow), findsNWidgets(3));
      // No text may be invented: a skeleton that printed "₹0" would be
      // asserting data before the data exists.
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('are not tappable and are hidden from screen readers', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          GestureDetector(
            onTap: () => taps++,
            child: const SkeletonList(itemCount: 2),
          ),
        ),
      );

      await tester.tap(find.byType(SkeletonList), warnIfMissed: false);
      await tester.pump();

      // IgnorePointer swallows the tap: a customer tapping a placeholder has
      // been given nothing, and must not trigger an action.
      expect(taps, 0);

      // Placeholder blocks are explicitly excluded from the semantics tree, so
      // a screen reader does not announce them as content.
      final finder = find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.excludeSemantics == true,
      );
      expect(finder, findsWidgets);
    });

    testWidgets('do not scroll under the finger', (tester) async {
      // A scrollable skeleton invites the customer to scroll placeholders.
      await tester.pumpWidget(_host(const SkeletonList(itemCount: 20)));
      final list = tester.widget<ListView>(find.byType(ListView));
      expect(list.physics, isA<NeverScrollableScrollPhysics>());
    });
  });
}
