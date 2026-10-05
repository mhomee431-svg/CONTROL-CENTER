import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:hyperlocal_app/features/support/data/support_repository.dart';
import 'package:hyperlocal_app/features/support/presentation/screens/support_issues_screen.dart';

/// The gate reads `authControllerProvider.status`, so the status is stubbed
/// rather than driven through a real sign-in.
class _StubAuthController extends AuthController {
  _StubAuthController(this.initialStatus);

  final AuthStatus initialStatus;

  @override
  AuthState build() => AuthState(status: initialStatus);
}

/// Serves a fixed ticket history, or a fixed failure.
class _FakeSupportRepository implements SupportRepository {
  _FakeSupportRepository({this.issues = const [], this.failure});

  final List<SupportIssue> issues;

  /// When set, the history read throws — the "could not load" path.
  final Object? failure;

  int listCalls = 0;

  @override
  Future<SupportSubmitResult> submitIssue({
    required SupportIssueCategory category,
    required String description,
    String? contactEmail,
  }) async => SupportSubmitResult.success;

  @override
  Future<List<SupportIssue>> listMyIssues() async {
    listCalls++;
    final error = failure;
    if (error != null) throw error;
    return issues;
  }
}

/// Builds a ticket through the REAL parser, so a decoding regression fails these
/// tests instead of being masked by hand-built objects.
SupportIssue _issue({
  required int id,
  String status = 'OPEN',
  String statusLabel = 'Open',
  String? notes,
  DateTime? resolvedAt,
  String category = 'CUST_WRONG_PRICE',
  String categoryLabel = 'Wrong price',
}) {
  final issue = SupportIssue.tryParse({
    'id': id,
    'reference': 'HL-$id',
    'category': category,
    'category_label': categoryLabel,
    'description': 'The price shown for Paracetamol is wrong at my local shop.',
    'status': status,
    'status_label': statusLabel,
    'priority': 'MEDIUM',
    'created_at': '2026-03-12T10:00:00Z',
    'resolution_notes': notes,
    'resolved_at': resolvedAt?.toIso8601String(),
  });
  expect(issue, isNotNull, reason: 'seed ticket $id must decode');
  return issue!;
}

GoRouter _router() {
  return GoRouter(
    initialLocation: '/support/issues',
    routes: [
      GoRoute(
        path: '/support/issues',
        builder: (_, _) => const SupportIssuesScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (_, _) =>
            Scaffold(appBar: AppBar(), body: const Text('LoginPage')),
      ),
      GoRoute(
        path: '/help',
        builder: (_, _) =>
            Scaffold(appBar: AppBar(), body: const Text('HelpPage')),
      ),
    ],
  );
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _FakeSupportRepository repository, {
  AuthStatus status = AuthStatus.authenticated,
  bool settle = true,
}) async {
  // Tall surface so every ticket row is built.
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith(() => _StubAuthController(status)),
      supportRepositoryProvider.overrideWithValue(repository),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: _router()),
    ),
  );

  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // `pumpAndSettle` cannot be used while the sign-in gate is on screen: the
    // screen shows an indeterminate progress indicator behind the sheet, and an
    // indeterminate spinner never settles. Pumping fixed frames lets the sheet's
    // entrance animation finish instead.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
  return container;
}

void main() {
  testWidgets('reports are rendered with the status the backend sent', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeSupportRepository(
        issues: [
          _issue(id: 42),
          _issue(
            id: 43,
            status: 'IN_PROGRESS',
            statusLabel: 'In progress',
            categoryLabel: 'Availability mismatch',
          ),
        ],
      ),
    );

    // The reference is what the customer quotes to support.
    expect(find.text('HL-42'), findsOneWidget);
    expect(find.text('HL-43'), findsOneWidget);
    // The display wording is the backend's `status_label`, not a local guess.
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
    expect(find.text('Wrong price'), findsOneWidget);
    expect(find.text('Reported 12 Mar 2026'), findsNWidgets(2));
  });

  testWidgets('a resolved report shows support\u2019s answer', (tester) async {
    await _pump(
      tester,
      _FakeSupportRepository(
        issues: [
          _issue(
            id: 44,
            status: 'RESOLVED',
            statusLabel: 'Resolved',
            notes: 'Confirmed and corrected with the shop.',
            resolvedAt: DateTime(2026, 3, 14),
          ),
        ],
      ),
    );

    expect(find.text('Resolved'), findsOneWidget);
    expect(find.text('Resolved 14 Mar 2026'), findsOneWidget);
    expect(find.text('Confirmed and corrected with the shop.'), findsOneWidget);
  });

  testWidgets('an unreadable status renders as reported, never invented', (
    tester,
  ) async {
    // A status this build has never seen must not be reworded into a
    // comfortable guess, and must not render as a blank either — a blank reads
    // as "nothing is wrong".
    await _pump(
      tester,
      _FakeSupportRepository(
        issues: [_issue(id: 45, status: '', statusLabel: '')],
      ),
    );

    expect(find.text('Unknown'), findsOneWidget);
    expect(find.text('Reported 12 Mar 2026'), findsOneWidget);
  });

  testWidgets('an empty history offers a way to report something', (
    tester,
  ) async {
    // Every list's empty state must give the customer something useful to do.
    await _pump(tester, _FakeSupportRepository());

    expect(find.text('No reports yet'), findsOneWidget);
    expect(find.text('Report an issue'), findsOneWidget);
  });

  testWidgets('a failed load offers a retry, never an empty history', (
    tester,
  ) async {
    // The honesty guard: reporting "no reports" for a request that never
    // arrived would send the customer off to file the same report again.
    final repository = _FakeSupportRepository(failure: Exception('offline'));
    await _pump(tester, repository);

    expect(find.text('No reports yet'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);

    // Retry actually re-reads rather than being a decorative button.
    final callsBefore = repository.listCalls;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(repository.listCalls, greaterThan(callsBefore));
  });

  testWidgets('a guest is asked to sign in and their reports are never read', (
    tester,
  ) async {
    // The gate must come BEFORE the read. Fetching first and merely hiding the
    // result would still be a request made with no identity behind it, and the
    // customer would be shown a spinner instead of the reason they are waiting.
    final repository = _FakeSupportRepository(issues: [_issue(id: 46)]);
    await _pump(
      tester,
      repository,
      status: AuthStatus.unauthenticated,
      // The gate's sheet is on screen, so nothing can settle (see `_pump`).
      settle: false,
    );

    // The real guest experience: the sign-in sheet, over the screen underneath.
    expect(find.text('Sign in to continue'), findsOneWidget);
    // The history was never requested, and never claimed to be empty.
    expect(repository.listCalls, 0);
    expect(find.text('No reports yet'), findsNothing);
    expect(find.text('HL-46'), findsNothing);
  });

  testWidgets('a closed report keeps the backend wording', (tester) async {
    // A terminal state must still be listed and still read as the server's
    // wording — not hidden, and not reworded into something friendlier.
    await _pump(
      tester,
      _FakeSupportRepository(
        issues: [_issue(id: 47, status: 'CLOSED', statusLabel: 'Closed')],
      ),
    );

    expect(find.text('HL-47'), findsOneWidget);
    expect(find.text('Closed'), findsOneWidget);
    expect(find.text('No reports yet'), findsNothing);
  });
}
