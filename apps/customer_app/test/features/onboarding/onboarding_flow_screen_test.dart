import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal_app/core/storage/local_storage_driver.dart';
import 'package:hyperlocal_app/core/storage/secure_storage_service.dart';
import 'package:hyperlocal_app/features/onboarding/data/onboarding_repository.dart';
import 'package:hyperlocal_app/features/onboarding/presentation/screens/onboarding_flow_screen.dart';

/// Fake secure storage — the repository only reads the legacy onboarding key
/// from it, so a map-backed no-op is enough.
class _FakeSecureStorage implements SecureStorageService {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late InMemoryStorageDriver local;
  late _FakeSecureStorage secure;

  setUp(() {
    local = InMemoryStorageDriver();
    secure = _FakeSecureStorage();
  });

  test('first launch reports the tour as not completed', () async {
    final repository = OnboardingRepository(local, secure);
    expect(await repository.hasCompletedOnboarding(), isFalse);
  });

  test(
    'completion is persisted and survives a new repository instance',
    () async {
      final repository = OnboardingRepository(local, secure);
      await repository.markOnboardingComplete();

      expect(await repository.hasCompletedOnboarding(), isTrue);
      // A fresh instance (e.g. after an app restart) still sees completion.
      expect(
        await OnboardingRepository(local, secure).hasCompletedOnboarding(),
        isTrue,
      );
    },
  );

  test('the legacy secure-storage flag migrates existing installs', () async {
    await secure.write(key: 'has_onboarded', value: 'true');
    final repository = OnboardingRepository(local, secure);
    expect(await repository.hasCompletedOnboarding(), isTrue);
  });

  testWidgets('the tour shows exactly the five spec screens and finishes', (
    WidgetTester tester,
  ) async {
    // A modern phone viewport keeps the side-icon rail within its bounds.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/onboarding',
      routes: [
        GoRoute(
          path: '/onboarding',
          builder: (_, _) => const OnboardingFlowScreen(),
        ),
        GoRoute(
          path: '/welcome',
          builder: (_, _) => const Scaffold(body: Text('WELCOME')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageDriverProvider.overrideWithValue(local),
          secureStorageProvider.overrideWithValue(secure),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    // Screen 1
    expect(find.text('Welcome'), findsOneWidget);
    expect(find.text('1 / 5'), findsOneWidget);

    for (final title in <String>[
      'Search Nearby Products',
      'Compare Price & Availability',
      'Find Shop & Get Directions',
      'Get Started',
    ]) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      // The mock phone screen repeats some titles, so assert on the step
      // header (keyed) rather than on any matching text on the page.
      final headerTexts = tester
          .widgetList<Text>(find.byKey(const Key('onboardingStepTitle')))
          .map((widget) => widget.data)
          .toList();
      expect(
        headerTexts,
        contains(title),
        reason: 'Expected step "$title" to be the current screen header',
      );
    }

    expect(find.text('5 / 5'), findsOneWidget);

    // Finishing the tour persists completion and moves to the brand welcome.
    // Target the CTA button itself: step 5's title has the same label.
    await tester.tap(find.widgetWithText(ElevatedButton, 'Get Started'));
    await tester.pumpAndSettle();

    expect(find.text('WELCOME'), findsOneWidget);
    expect(await local.getString(OnboardingRepository.storageKey), 'true');
  });
}
