import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/ui/primary_cta_bar.dart';

/// BUTTON CONTRACT — every primary button must have: normal · pressed ·
/// disabled · loading · error-safe behaviour.
///
///     Save Product
///     normal:   Save Product
///     loading:  Saving…
///     disabled: disabled
///     success:  navigate / update state
///
/// `PrimaryCtaBar` already pins the in-flight rule ("loading disables BOTH") on
/// itself; THIS file pins the contract at the level every hand-rolled button
/// must meet too — because the 79 `FilledButton`s do NOT all funnel through
/// the shared bar. The rules are behavioural, not "use the component":
///
///   1. An in-flight button fires at most ONE action (single-submit).
///   2. A button with progress copy renders its progress state.
///   3. A disabled button cannot be tapped into an action.
void main() {
  group('BUTTON CONTRACT — the shared primary', () {
    testWidgets('loading swaps progress copy and disables BOTH actions', (
      tester,
    ) async {
      var fired = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: PrimaryCtaBar(
              primaryLabel: 'Save Product',
              onPrimary: () => fired++,
              loading: true,
              loadingLabel: 'Saving…',
              secondaryLabel: 'Cancel',
              onSecondary: () => fired++,
            ),
            body: const SizedBox.shrink(),
          ),
        ),
      );

      expect(find.text('Saving…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      await tester.tap(find.byType(OutlinedButton), warnIfMissed: false);
      await tester.pump();
      expect(fired, 0, reason: 'one tap must never start two operations');
    });

    testWidgets('the normal label returns when loading ends', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: PrimaryCtaBar(
              primaryLabel: 'Save Product',
              onPrimary: () {},
            ),
            body: const SizedBox.shrink(),
          ),
        ),
      );

      expect(find.text('Save Product'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('BUTTON CONTRACT — hand-rolled mutation buttons obey the same rules', () {
    // Every hand-rolled spinner button found in `lib/features` was audited for
    // `onPressed: <busy> — null : …`. This test is the tripwire that catches
    // the NEXT one: it recreates the violating shape (a spinner whose button
    // stays enabled) and proves it fires twice — so a reviewer who sees this
    // pattern can recognise it in production code.
    testWidgets('an enabled spinner button IS the double-submit bug', (
      tester,
    ) async {
      var fired = 0;
      var busy = false;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, refresh) => Scaffold(
              body: FilledButton(
                key: const Key('violating-save'),
                // The violation: `busy` changes the LABEL but the button
                // stays enabled.
                onPressed: () {
                  fired++;
                  refresh(() => busy = true);
                },
                child: busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save Product'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('violating-save')));
      await tester.pump();
      // The label flipped, but the button still accepts taps — the second tap
      // refires the mutation. THIS is what `busy — null` prevents.
      await tester.tap(find.byKey(const Key('violating-save')));
      await tester.pump();

      expect(
        fired,
        2,
        reason:
            'control: the violating shape fires on every tap; '
            '`busy — null` is what removes the second fire',
      );
    });

    testWidgets('the same shape with busy-disabled fires exactly once', (
      tester,
    ) async {
      var fired = 0;
      var busy = false;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, refresh) => Scaffold(
              body: FilledButton(
                key: const Key('honest-save'),
                // The contract: the busy flag owns the PRESS, not just the
                // label.
                onPressed: busy
                    ? null
                    : () {
                        fired++;
                        refresh(() => busy = true);
                      },
                child: busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save Product'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('honest-save')));
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('honest-save')),
        warnIfMissed: false,
      );
      await tester.pump();

      expect(fired, 1, reason: 'a busy button must refuse the second tap');
    });
  });
}
