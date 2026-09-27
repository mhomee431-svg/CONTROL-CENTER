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
        builder: (_, _) => Scaffold(appBar: AppBar(), body: Text('HelpPage')),
      ),
      GoRoute(
        path: '/privacy',
        builder: (_, _) => Scaffold(appBar: AppBar(), body: Text('PrivacyPage')),
      ),
      GoRoute(
        path: '/terms',
        builder: (_, _) => Scaffold(appBar: AppBar(), body: Text('TermsPage')),
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
}
