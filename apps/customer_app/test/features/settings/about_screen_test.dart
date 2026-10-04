import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal_app/features/auth/domain/auth_service.dart'
    show authAppVersion;
import 'package:hyperlocal_app/features/settings/presentation/screens/about_screen.dart';

GoRouter _router() {
  return GoRouter(
    initialLocation: '/about',
    routes: [
      GoRoute(path: '/about', builder: (_, _) => const AboutScreen()),
      GoRoute(
        path: '/help',
        builder: (_, _) =>
            Scaffold(appBar: AppBar(), body: const Text('HelpPage')),
      ),
      GoRoute(
        path: '/privacy',
        builder: (_, _) =>
            Scaffold(appBar: AppBar(), body: const Text('PrivacyPage')),
      ),
      GoRoute(
        path: '/terms',
        builder: (_, _) =>
            Scaffold(appBar: AppBar(), body: const Text('TermsPage')),
      ),
    ],
  );
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the app identity and live version', (tester) async {
    await _pump(tester);

    expect(find.text('Hyperlocal'), findsOneWidget);
    // The version is the same constant the device reports to the backend,
    // so About can never drift from what the server thinks is installed.
    expect(find.text('Version $authAppVersion'), findsOneWidget);
  });

  testWidgets('links to help, privacy policy and terms', (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('aboutPrivacyTile')));
    await tester.pumpAndSettle();
    expect(find.text('PrivacyPage'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('aboutTermsTile')));
    await tester.pumpAndSettle();
    expect(find.text('TermsPage'), findsOneWidget);
  });

  testWidgets('environment is shown for build diagnosis', (tester) async {
    await _pump(tester);

    // A mis-pointed build is far easier to triage when the customer can
    // read which API the app is talking to.
    expect(find.byKey(const Key('aboutEnvironmentTile')), findsOneWidget);
    expect(find.text('Environment'), findsOneWidget);
  });

  testWidgets('the environment row copies diagnostics instead of doing nothing', (
    tester,
  ) async {
    await _pump(tester);

    // The row used to be drawn exactly like its navigating neighbours and then
    // ignore the tap — a dead control. It now performs a real action.
    //
    // `pumpAndSettle` alone is NOT enough: the confirmation is posted after an
    // `await` on the clipboard, which resolves on a later microtask, and
    // `pumpAndSettle` can return before that lands. An extra pump drains it.
    await tester.tap(find.byKey(const Key('aboutEnvironmentTile')));
    await tester.pumpAndSettle();
    await tester.pump();

    // A copy glyph, not a navigation chevron: a chevron would promise a
    // destination screen that does not exist. Scoped to THIS tile — the
    // navigating rows beside it legitimately keep their chevrons.
    final tile = find.byKey(const Key('aboutEnvironmentTile'));
    expect(
      find.descendant(of: tile, matching: find.byIcon(Icons.copy_all_outlined)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tile, matching: find.byIcon(Icons.chevron_right)),
      findsNothing,
      reason: 'a row that copies must not advertise a destination',
    );

    // And the customer is told what happened, in terms of the action.
    expect(find.textContaining('Build details copied'), findsOneWidget);

    // No navigation occurred — the About screen is still the visible page.
    expect(find.text('Environment'), findsOneWidget);
  });
}
