// Debounced search — the search box must not refilter on every keystroke.
//
// The products / inventory / price-list search boxes filter a local catalog
// per keystroke. ProductSearch + ProductQueryCache make each filter cheap,
// but running the full query (and its provider rebuild) once per glyph on a
// 2,000-row shop still lags the keyboard. DebouncedSearchField coalesces
// keystrokes with a 300 ms timer and applies the settled value — plus the
// still-pending text, immediately, on focus loss / submit / clear.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hyperlocal_shopkeeper_app/core/ui/debounced_search_field.dart';

void main() {
  testWidgets('fires onChanged only after the debounce delay',
      (tester) async {
    String? firedValue;
    int firedCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DebouncedSearchField(
            onChanged: (v) {
              firedValue = v;
              firedCount++;
            },
            delay: const Duration(milliseconds: 300),
          ),
        ),
      ),
    );

    final field = find.byKey(const Key('search_field'));
    await tester.enterText(field, 'amul');

    // No fire yet — the first keystroke started the timer.
    expect(firedCount, 0);
    expect(firedValue, isNull);

    // Advance just shy of the delay — still pending.
    await tester.pump(const Duration(milliseconds: 299));
    expect(firedCount, 0);

    // Past the delay — the accumulated text fires once.
    await tester.pump(const Duration(milliseconds: 2));
    expect(firedCount, 1);
    expect(firedValue, 'amul');
  });

  testWidgets('does not fire on an intermediate keystroke while typing fast',
      (tester) async {
    String? lastFired;
    int fireCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DebouncedSearchField(
            onChanged: (v) {
              lastFired = v;
              fireCount++;
            },
            delay: const Duration(milliseconds: 300),
          ),
        ),
      ),
    );

    final field = find.byKey(const Key('search_field'));

    for (final text in ['a', 'am', 'amu', 'amul']) {
      await tester.enterText(field, text);
      // Between keystrokes the timer is reset, so nothing fires yet.
      await tester.pump(const Duration(milliseconds: 50));
      expect(fireCount, 0, reason: 'no fire while still typing "$text"');
    }

    // The last keystroke's 300 ms timer is what delivers the value.
    await tester.pump(const Duration(milliseconds: 301));
    expect(fireCount, 1);
    expect(lastFired, 'amul');
  });

  testWidgets('clearing via the clear button empties the field and fires empty',
      (tester) async {
    String? firedValue;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DebouncedSearchField(
            onChanged: (v) => firedValue = v,
            delay: Duration.zero,
          ),
        ),
      ),
    );

    final field = find.byKey(const Key('search_field'));
    await tester.enterText(field, 'milk');
    await tester.pump();
    expect(firedValue, 'milk');

    final clear = find.byIcon(Icons.clear);
    await tester.tap(clear);
    await tester.pump();

    expect(firedValue, '');
    expect(find.text('milk'), findsNothing);
  });

  testWidgets('does not fire the debounce timer after dispose',
      (tester) async {
    // Regression: a timer scheduled before dispose must not call back into a
    // dead widget.
    String? firedValue;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DebouncedSearchField(
            onChanged: (v) => firedValue = v,
            delay: const Duration(milliseconds: 300),
          ),
        ),
      ),
    );

    final field = find.byKey(const Key('search_field'));
    await tester.enterText(field, 'amul');
    // Removes the widget BEFORE the timer fires.
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('x'))));
    await tester.pump(const Duration(milliseconds: 350));

    // No callback — the timer was cancelled in dispose().
    expect(firedValue, isNull);
  });

  testWidgets('losing focus flushes the pending text exactly once',
      (tester) async {
    String? lastFired;
    int fireCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              DebouncedSearchField(
                onChanged: (v) {
                  lastFired = v;
                  fireCount++;
                },
                delay: const Duration(milliseconds: 300),
              ),
              const TextField(key: Key('other_field')),
            ],
          ),
        ),
      ),
    );

    final field = find.byKey(const Key('search_field'));
    await tester.enterText(field, 'amul');
    // Still typing — nothing delivered yet.
    await tester.pump(const Duration(milliseconds: 50));
    expect(fireCount, 0);

    // Tapping elsewhere removes focus: the pending text is applied NOW, so
    // rows a shopkeeper looks at after typing always match what they typed.
    await tester.tap(find.byKey(const Key('other_field')));
    await tester.pump();
    expect(fireCount, 1);
    expect(lastFired, 'amul');

    // And the spent timer cannot deliver it a second time.
    await tester.pump(const Duration(milliseconds: 400));
    expect(fireCount, 1);
  });

  testWidgets('settling the frame queue does not consume the debounce',
      (tester) async {
    // Regression guard for pumpAndSettle-style test harnesses: settling
    // pending FRAMES must not advance the debounce TIMER, and a tap that
    // lands while unfocused must still flush the typed text first.
    String? lastFired;
    int fireCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              DebouncedSearchField(
                onChanged: (v) {
                  lastFired = v;
                  fireCount++;
                },
                delay: const Duration(milliseconds: 300),
              ),
              const TextField(key: Key('other_field')),
            ],
          ),
        ),
      ),
    );

    final field = find.byKey(const Key('search_field'));
    await tester.enterText(field, 'amul');
    await tester.pumpAndSettle();
    expect(fireCount, 0, reason: 'settling frames must not fire the timer');

    await tester.tap(find.byKey(const Key('other_field')));
    await tester.pump();
    expect(fireCount, 1);
    expect(lastFired, 'amul');

    await tester.pump(const Duration(milliseconds: 400));
    expect(fireCount, 1, reason: 'the spent timer must not double-deliver');
  });
  testWidgets('onSubmitted flushes the pending text exactly once',
      (tester) async {
    String? submittedValue;
    String? changedValue;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DebouncedSearchField(
            onChanged: (v) => changedValue = v,
            onSubmitted: (v) => submittedValue = v,
            delay: const Duration(milliseconds: 300),
          ),
        ),
      ),
    );

    final field = find.byKey(const Key('search_field'));
    await tester.enterText(field, 'sugar');
    // Submit without letting the debounce timer fire.
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();

    expect(submittedValue, 'sugar');
    // The pending debounce is flushed through onChanged as well so the
    // filter sees the submitted text.
    expect(changedValue, 'sugar');
  });
}
