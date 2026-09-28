import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/theme/app_theme.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/domain/import_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/presentation/widgets/import_status_view.dart';

/// The point of [importStatusTone] is that the confirm/result screen and the
/// history list cannot disagree about what a status LOOKS like. These tests pin
/// the mapping, and pin the one row that used to contradict its own label.
void main() {
  group('importStatusTone', () {
    test('success is the only green state', () {
      expect(
        importStatusTone(ImportJobStatusValue.completed).color,
        AppTheme.verifiedGreen,
      );
    });

    test('failure is the only red state', () {
      expect(
        importStatusTone(ImportJobStatusValue.failed).color,
        AppTheme.rejectedRed,
      );
    });

    test('partial is amber — neither success nor failure', () {
      final tone = importStatusTone(ImportJobStatusValue.partial);
      expect(tone.color, AppTheme.pendingAmber);
      expect(tone.color, isNot(AppTheme.verifiedGreen));
      expect(tone.color, isNot(AppTheme.rejectedRed));
    });

    test('queued and processing look identical — both mean "working on it"', () {
      final queued = importStatusTone(ImportJobStatusValue.queued);
      final processing = importStatusTone(ImportJobStatusValue.processing);
      expect(queued.icon, processing.icon);
      expect(queued.color, processing.color);
    });

    test('every state renders a real icon, and the OUTCOMES are distinct', () {
      final states = [
        ImportJobStatusValue.validating,
        ImportJobStatusValue.awaitingConfirmation,
        ImportJobStatusValue.queued,
        ImportJobStatusValue.processing,
        ImportJobStatusValue.completed,
        ImportJobStatusValue.partial,
        ImportJobStatusValue.failed,
      ];
      // Every status must map to a real icon, never a zero/null value that
      // would draw an invisible glyph.
      for (final s in states) {
        expect(importStatusTone(s).icon, isNotNull, reason: s);
      }
      // The three terminal OUTCOMES must be told apart at a glance. QUEUED and
      // PROCESSING are deliberately NOT in this set: they are the same thing to
      // a shopkeeper ("working on it") and share an icon on purpose.
      const outcomes = [
        ImportJobStatusValue.completed,
        ImportJobStatusValue.partial,
        ImportJobStatusValue.failed,
      ];
      expect(
        outcomes.map((s) => importStatusTone(s).icon).toSet().length,
        outcomes.length,
      );
    });

    test('a status the backend adds later degrades, never throws', () {
      // The client must not invent a state, but it must not crash on one it has
      // never seen either — a future backend enum value still renders.
      final tone = importStatusTone('SOMETHING_NEW');
      expect(tone.icon, isNotNull);
      expect(tone.color, isNotNull);
    });

    test('the legacy VALIDATED alias reads as still-validating, not complete', () {
      // THE regression this unification fixed: the history row used to draw a
      // GREEN TICK for VALIDATED while the chip beside it read "Validating",
      // because the label helper treats that legacy status as in-flight.
      final tone = importStatusTone(ImportJobStatusValue.validated);
      expect(ImportJobStatusValue.label(ImportJobStatusValue.validated),
          'Validating');
      expect(tone.color, isNot(AppTheme.verifiedGreen));
      expect(tone.color, importStatusTone(ImportJobStatusValue.validating).color);
    });
  });

  group('ImportStatusView', () {
    testWidgets('renders the title, message and tone it is given',
        (tester) async {
      const tone = ImportStatusTone(
        icon: Icons.check_circle_outline,
        color: AppTheme.verifiedGreen,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ImportStatusView(
              tone: tone,
              title: 'Import successful',
              message: '12 rows processed — all successful.',
              titleKey: Key('import-result-success'),
            ),
          ),
        ),
      );

      expect(find.text('Import successful'), findsOneWidget);
      expect(find.text('12 rows processed — all successful.'), findsOneWidget);
      // The icon comes from the tone, not from a per-screen decision.
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      final icon = tester.widget<Icon>(find.byIcon(Icons.check_circle_outline));
      expect(icon.color, AppTheme.verifiedGreen);
    });

    testWidgets('the titleKey identifies WHICH outcome rendered', (tester) async {
      // Lets a test assert the state without depending on the copy, which is
      // allowed to change.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ImportStatusView(
              tone: ImportStatusTone(
                icon: Icons.warning_amber_outlined,
                color: AppTheme.pendingAmber,
              ),
              title: 'Partially imported',
              message: '3 successful, 1 failed.',
              titleKey: Key('import-result-partial'),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('import-result-partial')), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);
    });
  });
}