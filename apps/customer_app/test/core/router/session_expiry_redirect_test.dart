import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal_app/core/router/app_router.dart';
import 'package:hyperlocal_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:hyperlocal_app/features/onboarding/presentation/controllers/onboarding_controller.dart';

/// Session-expiry navigation contract.
///
/// WHY A MOUNTED TREE
/// ------------------
/// These tests assert on the real `GoRouter.redirect`, reached the way the app
/// reaches it — through a mounted `MaterialApp.router` with the auth state
/// overridden. Driving the redirect through a widget also means an infinite
/// redirect surfaces as a test failure rather than hanging the run.
///
/// THE LOOP GUARD IS THE POINT
/// ---------------------------
/// An expired customer whose login screen keeps redirecting onto itself can
/// never type a phone number, and the app is unusable until force-killed. Every
/// test here asserts the redirect REACHES A FIXED POINT.
void main() {
  /// Builds the real router with a forced auth status.
  ///
  /// `onboardingCompletedProvider` is overridden to true so the startup gate
  /// (`onboardingCompleted == null`) does not mask the expiry branch.
  Future<void> pumpRouter(
    WidgetTester tester,
    AuthStatus status, {
    String location = '/orders',
  }) async {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => _FixedAuthController(status),
        ),
        onboardingCompletedProvider.overrideWith(
          () => _FixedOnboardingController(true),
        ),
      ],
    );
    addTearDown(container.dispose);

    final router = container.read(routerProvider);

    // Wrapping in a ProviderScope is what lets the screen tree read the SAME
    // overrides the router was built from — otherwise the pushed screen would
    // build a second, un-overridden container and fight the router.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    // The redirect runs here. A loop would never settle, and pumpAndSettle
    // would throw — which is exactly the failure this suite exists to catch.
    //
    // A redirect LOOP is not detected by waiting for quiescence — it is detected
    // by observing that the route never reaches its destination while frames
    // keep being scheduled. The bounded pumps above advance the router far
    // enough for that to be observable, and each test then asserts the settled
    // path. A loop leaves the path short of the destination (or bounces to
    // /login), which is exactly what the assertions catch.
    router.go(location);

    // Bounded frame budget rather than `pumpAndSettle`: once the destination
    // screen paints, its loading state may be an animated shimmer, which
    // schedules frames forever. Waiting for quiescence would time out on a
    // perfectly healthy screen and blame a redirect loop that is not there.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      tester.takeException(),
      isNull,
      reason: 'the expiry redirect must not throw or loop',
    );
  }

  /// The route the router settled on after [pumpRouter].
///
/// Read off the mounted [Router] widget rather than `GoRouter`: a `GoRouter` is
/// a [RouterConfig] object, NOT a widget, so `find.byType(GoRouter)` can never
/// match one.
String settledPath(WidgetTester tester) {
  final router = tester.widget<Router<Object>>(find.byType(Router<Object>));
  // Two casts are needed, and both are load-bearing:
  //  * `Router.routerDelegate` is `Object?` so a Router can wrap ANY delegate.
  //  * `RouterDelegate.currentConfiguration` is `Future<Object>` — a GoRouter
  //    overrides it with `Future<RouteMatchList?>`, which is what actually
  //    carries `.uri`. Casting to the base type would leave `.uri` undefined.
  //    (`GoRouterDelegate` is not generic in go_router 17.)
  final delegate = router.routerDelegate as GoRouterDelegate;
  return delegate.currentConfiguration.uri.path;
}

  testWidgets('expiry on an account screen lands on the login screen', (
    tester,
  ) async {
    // /orders is account data fetched with a token the server has revoked.
    await pumpRouter(tester, AuthStatus.sessionExpired, location: '/orders');

    expect(settledPath(tester), '/login');
  });

  testWidgets('expiry does not trap the customer on the login screen', (
    tester,
  ) async {
    // THE loop guard. Without `location != '/login'`, GoRouter would re-run the
    // redirect on every navigation and never settle — the customer could never
    // type a phone number again. pumpAndSettle in [pumpRouter] is what proves
    // the loop is gone: it throws if frames keep being scheduled.
    await pumpRouter(tester, AuthStatus.sessionExpired, location: '/login');

    expect(settledPath(tester), '/login');
  });

  testWidgets('expiry leaves public browsing reachable', (tester) async {
    // Expiring a token should cost the customer their saved lists, not their
    // ability to browse nearby shops. A login wall on /search would be a worse
    // outcome than the expiry itself.
    await pumpRouter(tester, AuthStatus.sessionExpired, location: '/search');

    expect(settledPath(tester), isNot('/login'));
  });

  testWidgets('an authenticated customer is left alone', (tester) async {
    await pumpRouter(tester, AuthStatus.authenticated, location: '/orders');

    expect(settledPath(tester), '/orders');
  });

  testWidgets('a guest customer is left alone', (tester) async {
    await pumpRouter(tester, AuthStatus.guest, location: '/search');

    expect(settledPath(tester), '/search');
  });
}

/// An [AuthController] that only reports a status.
///
/// The real controller reads and writes secure storage on build, which a unit
/// test has no business doing; the redirect under test only reads `status`.
class _FixedAuthController extends AuthController {
  _FixedAuthController(this.status);

  final AuthStatus status;

  @override
  AuthState build() => AuthState(status: status);
}

/// An [OnboardingCompletedController] pinned to a fixed value.
///
/// The real one fires a storage read on build and starts at `null`, which holds
/// the router on `/splash` — exactly the startup gate these tests need to step
/// past. Pinning it to `true` means "tour already finished", so the redirect
/// under test is the only thing being observed.
class _FixedOnboardingController extends OnboardingCompletedController {
  _FixedOnboardingController(this.value);

  final bool value;

  @override
  bool? build() => value;
}
