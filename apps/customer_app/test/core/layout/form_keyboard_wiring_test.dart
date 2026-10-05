import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hyperlocal_app/core/layout/form_keyboard.dart';

void main() {
  group('the IME action matches the field position', () {
    test('every field but the last offers "next"', () {
      expect(FormKeyboard.actionFor(0, 3), TextInputAction.next);
      expect(FormKeyboard.actionFor(1, 3), TextInputAction.next);
    });

    test('the last field offers "done"', () {
      // Getting this backwards is the classic form bug: a form whose final field
      // says "next" strands the customer on a dead key with no way forward.
      expect(FormKeyboard.actionFor(2, 3), TextInputAction.done);
    });

    test('a single-field form is immediately "done"', () {
      expect(FormKeyboard.actionFor(0, 1), TextInputAction.done);
    });
  });

  group('advance walks the form then stops', () {
    // Pumped into a real tree on purpose: `FocusNode.requestFocus()` is a no-op
    // on a DETACHED node, so a test that just calls `advance` and checks
    // `hasFocus` passes nothing — or rather, fails for the wrong reason. Going
    // through the IME action also exercises the real path the customer takes.
    Future<void> pumpForm(WidgetTester tester, List<FocusNode> nodes) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                for (var i = 0; i < nodes.length; i++)
                  TextField(
                    focusNode: nodes[i],
                    textInputAction: FormKeyboard.actionFor(i, nodes.length),
                    onEditingComplete: () =>
                        FormKeyboard.advance(nodes: nodes, from: i),
                  ),
              ],
            ),
          ),
        ),
      );
      nodes.first.requestFocus();
      await tester.pumpAndSettle();
    }

    testWidgets('next moves focus to the following field', (tester) async {
      final nodes = [FocusNode(), FocusNode(), FocusNode()];
      addTearDown(() {
        for (final node in nodes) {
          node.dispose();
        }
      });
      await pumpForm(tester, nodes);
      expect(nodes.first.hasFocus, isTrue, reason: 'sanity: field 1 focused');

      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();

      expect(
        nodes[1].hasFocus,
        isTrue,
        reason: 'next must move to field 2, not submit',
      );
      expect(nodes.first.hasFocus, isFalse);
    });

    testWidgets('the final field closes the keyboard without submitting', (
      tester,
    ) async {
      // Deliberately NOT `TextInputAction.submit`: submitting from the last field
      // of a form the customer may not have finished is a data-loss bug, because
      // earlier fields can still be empty and validation rejects it for no
      // visible reason.
      final nodes = [FocusNode(), FocusNode()];
      addTearDown(() {
        for (final node in nodes) {
          node.dispose();
        }
      });
      await pumpForm(tester, nodes);

      nodes.last.requestFocus();
      await tester.pumpAndSettle();
      expect(nodes.last.hasFocus, isTrue);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        nodes.last.hasFocus,
        isFalse,
        reason: 'done must dismiss, not leave focus parked on the field',
      );
    });

    test('an empty field list is a no-op rather than a crash', () {
      expect(
        () => FormKeyboard.advance(nodes: const [], from: 0),
        returnsNormally,
      );
    });
  });

  group('every text input in the app declares an IME action', () {
    // WHY THIS GUARD EXISTS
    // ---------------------
    // The task this came from found 17 text inputs and only 4 declaring a
    // `textInputAction`. That ratio is invisible in review and impossible to
    // catch by testing one screen — a new form can regress it silently, and the
    // symptom only appears on a physical device with an IME.
    //
    // So this checks the whole `lib/` tree as a contract. It is deliberately a
    // source scan rather than a widget test: pumping every screen would need a
    // provider graph per screen and would still miss the ones nobody pumps.
    //
    // A field passes if it declares `textInputAction` or `onSubmitted` within the
    // next few lines. Both satisfy the customer; only one of them is the fix we
    // would have preferred, but the contract being enforced is "the behaviour is
    // deliberate", not "it was spelled a particular way".

    // No gaps remain. `request_quote_sheet.dart` was the last file with
    // unwired inputs, and it is now covered like the rest.
    //
    // It needed a real fix rather than a deletion: six controls, of which only
    // three are IME text entry (pickup, destination, notes). The dropdown, the
    // date field and the two steppers are deliberately NOT in the focus chain —
    // they have no IME action to advance from, and including them would make
    // `next` walk the customer into a date picker.
    const allowedUnwired = <String, String>{};

    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    final unwired = <String>[];

    for (final file in files) {
      final name = file.path.split(RegExp(r'[/\\]')).last;
      if (allowedUnwired.containsKey(name)) continue;

      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('TextField(') &&
            !lines[i].contains('TextFormField(')) {
          continue;
        }
        // Look ahead over the field's own argument list.
        final end = (i + 30).clamp(0, lines.length);
        final body = lines.sublist(i, end).join('\n');
        if (!body.contains('textInputAction:') &&
            !body.contains('onSubmitted:')) {
          unwired.add('$name:${i + 1}');
        }
      }
    }

    test('no input is left to the platform default', () {
      expect(
        unwired,
        isEmpty,
        reason:
            'these text inputs declare no textInputAction and no '
            'onSubmitted, so the IME shows a meaningless key:\n'
            '${unwired.join('\n')}',
      );
    });
  });
}
