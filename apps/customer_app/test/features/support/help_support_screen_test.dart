import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/features/support/data/support_repository.dart';
import 'package:hyperlocal_app/features/support/presentation/screens/help_support_screen.dart';

/// Scriptable repository so every outcome of the "submitted / failed /
/// success" matrix can be exercised without a backend.
class _FakeSupportRepository implements SupportRepository {
  _FakeSupportRepository(this.result);

  final SupportSubmitResult result;
  int calls = 0;

  @override
  Future<SupportSubmitResult> submitIssue({
    required SupportIssueCategory category,
    required String description,
    String? contactEmail,
  }) async {
    calls++;
    return result;
  }
}

Future<void> _pump(WidgetTester tester, SupportSubmitResult result) async {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      supportRepositoryProvider.overrideWithValue(
        _FakeSupportRepository(result),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: HelpSupportScreen()),
    ),
  );
  await tester.pumpAndSettle();

  // Move to the Report Issue tab.
  await tester.tap(find.text('Report Issue'));
  await tester.pumpAndSettle();
}

/// Fills the form with a valid description so submit passes validation.
Future<void> _fillAndSubmit(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('issueDescriptionField')),
    'The price shown for Paracetamol is wrong at my local shop.',
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('submitIssueButton')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a successful submission shows the success view', (tester) async {
    await _pump(tester, SupportSubmitResult.success);
    await _fillAndSubmit(tester);

    expect(find.text('Report Submitted!'), findsOneWidget);
    expect(find.byKey(const Key('issueSubmitError')), findsNothing);
  });

  testWidgets('a network failure is reported, never shown as success', (
    tester,
  ) async {
    await _pump(tester, SupportSubmitResult.networkFailure);
    await _fillAndSubmit(tester);

    // The old implementation returned true on failure, so this assertion is
    // the regression guard for a bug that told customers a report was sent
    // when nothing had left the device.
    expect(find.text('Report Submitted!'), findsNothing);
    expect(find.byKey(const Key('issueSubmitError')), findsOneWidget);
    expect(find.textContaining('could not reach our servers'), findsOneWidget);
  });

  testWidgets('a server rejection is reported distinctly', (tester) async {
    await _pump(tester, SupportSubmitResult.rejected);
    await _fillAndSubmit(tester);

    expect(find.text('Report Submitted!'), findsNothing);
    expect(find.textContaining('could not accept that report'), findsOneWidget);
  });

  testWidgets('a failed submission keeps what the customer wrote', (
    tester,
  ) async {
    // Losing a carefully written report to a network blip is a real loss.
    await _pump(tester, SupportSubmitResult.networkFailure);
    await _fillAndSubmit(tester);

    final field = tester.widget<TextFormField>(
      find.byKey(const Key('issueDescriptionField')),
    );
    expect(field.controller?.text, contains('Paracetamol'));
  });

  testWidgets('an empty description is blocked by validation', (tester) async {
    final repository = _FakeSupportRepository(SupportSubmitResult.success);
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [supportRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HelpSupportScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report Issue'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('submitIssueButton')));
    await tester.pumpAndSettle();

    // Nothing was sent.
    expect(repository.calls, 0);
    expect(find.text('Report Submitted!'), findsNothing);
  });

  testWidgets('FAQ and Contact tabs are present', (tester) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        supportRepositoryProvider.overrideWithValue(
          _FakeSupportRepository(SupportSubmitResult.success),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HelpSupportScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('FAQ'), findsOneWidget);
    expect(find.text('Contact'), findsOneWidget);
    expect(find.text('Report Issue'), findsOneWidget);
    // The FAQ list is actually populated.
    expect(find.text('How do I find a product near me?'), findsOneWidget);
  });
}
