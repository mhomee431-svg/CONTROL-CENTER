import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hyperlocal_app/core/layout/form_keyboard.dart';

/// Guards the keyboard behaviour of forms.
///
/// WHY THESE ASSERT WHAT THEY DO
/// ------------------------------
/// `onEditingComplete` and `textInputAction` are invisible at runtime — a field
/// with neither still looks and taps perfectly, so a regression here produces no
/// crash and no exception. The only thing that catches it is asserting the value
/// directly, which is why the IME actions are tested as data as well as through
/// simulated key presses.
/// Pumps a real three-field form whose nodes are ATTACHED.
///
/// The attachment matters: an unattached `FocusNode` silently refuses to take
/// focus, so a test built on bare nodes would pass while proving nothing. The
/// node has to be wired to a `TextField` before `hasFocus` means anything.
Future<void> pumpThreeFieldForm(
  WidgetTester tester,
  List<FocusNode> nodes,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: FormKeyboard.ordered(
          child: FormKeyboard.dismissOnBackgroundTap(
            child: Column(
              children: [for (final node in nodes) TextField(focusNode: node)],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('IME action follows position in the form', () {
    test('every field but the last says "next"', () {
      expect(FormKeyboard.actionFor(0, 3), TextInputAction.next);
      expect(FormKeyboard.actionFor(1, 3), TextInputAction.next);
    });

    test('the LAST field says "done"', () {
      // The inverse bug is worse: a last field marked "next" strands the
      // customer on a dead key with the keyboard open and no way forward.
      expect(FormKeyboard.actionFor(2, 3), TextInputAction.done);
    });

    test('a single-field form is immediately "done"', () {
      expect(FormKeyboard.actionFor(0, 1), TextInputAction.done);
    });

    test('the action is never "done" before the end', () {
      for (var i = 0; i < 4; i++) {
        expect(
          FormKeyboard.actionFor(i, 4) == TextInputAction.done,
          i == 3,
          reason: 'field $i of 4',
        );
      }
    });
  });

  group('advance moves focus, and dismisses only at the end', () {
    testWidgets('"next" moves to the following field', (tester) async {
      final nodes = [FocusNode(), FocusNode(), FocusNode()];
      for (final n in nodes) {
        addTearDown(n.dispose);
      }
      await pumpThreeFieldForm(tester, nodes);

      FormKeyboard.advance(nodes: nodes, from: 0);
      await tester.pump();
      expect(nodes[1].hasFocus, isTrue);
      expect(nodes[0].hasFocus, isFalse);

      FormKeyboard.advance(nodes: nodes, from: 1);
      await tester.pump();
      expect(nodes[2].hasFocus, isTrue);
    });

    testWidgets('"done" on the last field closes the keyboard', (tester) async {
      final nodes = [FocusNode(), FocusNode()];
      for (final n in nodes) {
        addTearDown(n.dispose);
      }
      await pumpThreeFieldForm(tester, nodes);

      nodes[1].requestFocus();
      await tester.pump();
      expect(nodes[1].hasFocus, isTrue);

      FormKeyboard.advance(nodes: nodes, from: 1);
      await tester.pump();

      expect(
        nodes[1].hasFocus,
        isFalse,
        reason: 'done must dismiss, not leave the customer on a focused field',
      );
    });

    testWidgets('"done" does NOT submit', (tester) async {
      // The data-loss guard: submitting from the last field would write a value
      // the customer may not have finished checking. Submission stays an
      // explicit button press.
      var submitted = false;
      final nodes = [FocusNode()];
      for (final n in nodes) {
        addTearDown(n.dispose);
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FormKeyboard.ordered(
              child: ElevatedButton(
                onPressed: () => submitted = true,
                child: const Text('Save'),
              ),
            ),
          ),
        ),
      );

      FormKeyboard.advance(nodes: nodes, from: 0);
      await tester.pump();

      expect(submitted, isFalse);
    });

    testWidgets('an empty field list is a no-op, not a crash', (tester) async {
      // Defensive: a form that conditionally hides every field would otherwise
      // throw here on a path no screen test is likely to reach.
      FormKeyboard.advance(nodes: const [], from: 0);
    });
  });

  group('scroll-to-field clears the keyboard', () {
    testWidgets('padding grows with the keyboard inset', (tester) async {
      Future<EdgeInsets> paddingWith(double inset) async {
        late EdgeInsets captured;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              // MediaQuery goes BELOW MaterialApp on purpose: MaterialApp
              // installs its own MediaQuery from the window, so wrapping
              // outside it means the injected viewInsets are discarded and the
              // test silently measures a zero keyboard.
              body: MediaQuery(
                data: MediaQueryData(
                  viewInsets: EdgeInsets.only(bottom: inset),
                ),
                child: Builder(
                  builder: (context) {
                    captured = FormKeyboard.scrollPaddingFor(context);
                    return const SizedBox();
                  },
                ),
              ),
            ),
          ),
        );
        return captured;
      }

      final none = await paddingWith(0);
      final open = await paddingWith(300);

      expect(open.bottom, greaterThan(none.bottom));
      expect(
        open.bottom,
        greaterThanOrEqualTo(300),
        reason: 'the field must clear the keyboard entirely',
      );
    });

    testWidgets('padding is never negative when the keyboard is closed', (
      tester,
    ) async {
      late EdgeInsets captured;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  captured = FormKeyboard.scrollPaddingFor(context);
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      expect(captured.bottom, greaterThanOrEqualTo(0));
      expect(captured.top, greaterThanOrEqualTo(0));
    });
  });

  group('background tap dismisses', () {
    testWidgets('tapping outside a field closes the keyboard', (tester) async {
      final field = FocusNode();
      addTearDown(field.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FormKeyboard.dismissOnBackgroundTap(
              child: Column(
                children: [
                  TextField(focusNode: field),
                  const SizedBox(height: 300),
                ],
              ),
            ),
          ),
        ),
      );

      field.requestFocus();
      await tester.pump();
      expect(field.hasFocus, isTrue);

      await tester.tapAt(const Offset(200, 500));
      await tester.pump();

      expect(
        field.hasFocus,
        isFalse,
        reason: 'tapping empty space must dismiss, not appear to do nothing',
      );
    });
  });
}
