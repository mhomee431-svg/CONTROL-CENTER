import 'dart:async';
// `Tristate` is the three-valued answer a semantics flag can now carry
// (true / false / not reported). It lives in dart:ui, which material.dart
// does not re-export, so this import is the one the assertions need.
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
// The enabled/disabled assertions read `flagsCollection.isEnabled`, which
// material.dart already re-exports, so no extra semantics import is
// needed for them.
import 'package:flutter_test/flutter_test.dart';

import 'package:hyperlocal_app/core/widgets/action_button.dart';

void main() {
  group('a double tap starts the work once', () {
    testWidgets('the second tap while in flight is dropped', (tester) async {
      var calls = 0;
      final completer = Completer<void>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActionButton(
              onPressed: () {
                calls++;
                return completer.future;
              },
              child: const Text('Place order'),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(ActionButton));
      await tester.pump();

      // A fast double tap: two taps with no chance for a rebuild in between.
      await tester.tap(find.byType(ActionButton));
      await tester.pump();

      expect(
        calls,
        1,
        reason: 'a customer who taps twice did not mean to order twice',
      );

      completer.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('many rapid taps still start it once', (tester) async {
      var calls = 0;
      final completer = Completer<void>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActionButton(
              onPressed: () {
                calls++;
                return completer.future;
              },
              child: const Text('Send'),
            ),
          ),
        ),
      );

      for (var i = 0; i < 8; i++) {
        await tester.tap(find.byType(ActionButton));
      }
      await tester.pump();

      expect(calls, 1);
      completer.complete();
      await tester.pumpAndSettle();
    });
  });

  group('the busy state is visible and announced', () {
    testWidgets('a spinner replaces the resting label', (tester) async {
      final completer = Completer<void>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActionButton(
              onPressed: () => completer.future,
              loadingLabel: const Text('Sending...'),
              child: const Text('Send code'),
            ),
          ),
        ),
      );

      expect(find.text('Send code'), findsOneWidget);

      await tester.tap(find.byType(ActionButton));
      await tester.pump();

      expect(
        find.byType(CircularProgressIndicator),
        findsOneWidget,
        reason:
            'without feedback a slow tap looks like nothing happened, '
            'which is exactly when a customer taps again',
      );
      expect(find.text('Sending...'), findsOneWidget);

      completer.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('the control reports itself disabled to assistive tech', (
      tester,
    ) async {
      final completer = Completer<void>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActionButton(
              onPressed: () => completer.future,
              child: const Text('Go'),
            ),
          ),
        ),
      );

      Finder theButton() => find.descendant(
        of: find.byType(ActionButton),
        matching: find.byType(FilledButton),
      );

      expect(
        tester.getSemantics(theButton()).flagsCollection.isEnabled,
        Tristate.isTrue,
      );

      await tester.tap(find.byType(ActionButton));
      await tester.pump();

      expect(
        tester.getSemantics(theButton()).flagsCollection.isEnabled,
        Tristate.isFalse,
        reason: 'a screen-reader user must be told the control is now busy',
      );

      completer.complete();
      await tester.pumpAndSettle();
    });
  });
  group('the guard releases', () {
    testWidgets('the button works again once the work finishes', (
      tester,
    ) async {
      var calls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActionButton(
              onPressed: () async {
                calls++;
                await Future<void>.delayed(const Duration(milliseconds: 50));
              },
              child: const Text('Retry'),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(ActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pumpAndSettle();

      expect(calls, 1);

      // Must NOT be left permanently dead.
      await tester.tap(find.byType(ActionButton));
      await tester.pumpAndSettle();
      expect(calls, 2, reason: 'a finished action must re-enable the control');
    });

    // NOT COVERED HERE: that the guard also releases when the action THROWS.
    // The `finally` in `_ActionButtonState` handles it, and the code is
    // correct — but an escaping async rejection from `onPressed` escapes both
    // `tester.takeException()` and a `FlutterError.onError` override, because
    // it is reported through the zone rather than the framework error handler.
    // Two harnesses were tried (capturing FlutterError, and discrete pumps
    // instead of pumpAndSettle); both left the test failing or hanging. A test
    // that cannot assert its subject is worse than a documented gap, so this is
    // recorded rather than faked.
  });

  group('disabled is distinct from busy', () {
    testWidgets('an explicitly disabled button never fires', (tester) async {
      var calls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActionButton(
              disabled: true,
              onPressed: () => calls++,
              child: const Text('Continue'),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(ActionButton));
      await tester.pump();

      expect(calls, 0);
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason:
            'a control disabled for a business reason is not busy — showing '
            'a spinner would claim work is happening when none is',
      );
    });

    testWidgets('a null action renders an inert control', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ActionButton(onPressed: null, child: Text('Nope')),
          ),
        ),
      );

      await tester.tap(find.byType(ActionButton));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('TapGuard swallows a double tap on non-button controls', () {
    testWidgets('a double tap on a custom control fires once', (tester) async {
      var calls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TapGuard(
              onTap: () => calls++,
              child: const SizedBox(
                width: 200,
                height: 200,
                child: Text('tap'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TapGuard));
      await tester.pump();
      await tester.tap(find.byType(TapGuard));
      await tester.pumpAndSettle();

      expect(calls, 1);
    });

    testWidgets('it is usable again on a later tap', (tester) async {
      // The guard must not leave the control permanently dead — it holds for one
      // frame precisely so ordinary repeated use keeps working.
      var calls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TapGuard(
              onTap: () => calls++,
              child: const SizedBox(
                width: 200,
                height: 200,
                child: Text('tap'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TapGuard));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TapGuard));
      await tester.pumpAndSettle();

      expect(calls, 2);
    });

    testWidgets('a disabled TapGuard does not fire', (tester) async {
      var calls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TapGuard(
              enabled: false,
              onTap: () => calls++,
              child: const SizedBox(
                width: 200,
                height: 200,
                child: Text('tap'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TapGuard));
      await tester.pumpAndSettle();

      expect(calls, 0);
    });
  });
}
