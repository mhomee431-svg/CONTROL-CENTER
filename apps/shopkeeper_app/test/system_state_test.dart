import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/state/system_state.dart';
import 'package:hyperlocal_shopkeeper_app/core/state/system_state_view.dart';

/// The system states: classification rules and the ONE shared renderer.
///
/// These states are the app's whole error/empty vocabulary, so the contract is
/// pinned here: a transport failure, a 503, a 403, a 401 and a plain 4xx each
/// map to the state that names the ONE way out that can actually help.

void main() {
  group('SystemStateSpec.classify — status / code evidence', () {
    test('no status + transport kind → offline vs network problem', () {
      expect(
        SystemStateSpec.classify(failureKind: ApiFailureKind.offline),
        SystemState.offline,
      );
      expect(
        SystemStateSpec.classify(failureKind: ApiFailureKind.timeout),
        SystemState.timeout,
      );
      // No response at all from an unknown transport failure == unreachable.
      expect(
        SystemStateSpec.classify(failureKind: ApiFailureKind.unknown),
        SystemState.networkError,
      );
    });

    test('503 / SERVICE_UNAVAILABLE → maintenance; 5xx → server error', () {
      expect(
        SystemStateSpec.classify(statusCode: 503),
        SystemState.maintenance,
      );
      expect(
        SystemStateSpec.classify(errorCode: 'STORAGE_UNAVAILABLE'),
        SystemState.maintenance,
      );
      expect(
        SystemStateSpec.classify(
          statusCode: 500,
          errorCode: 'INTERNAL_ERROR',
        ),
        SystemState.serverError,
      );
    });

    test('401 splits by the evidence the backend puts in the message', () {
      // `dependencies.py` raises UNAUTHORIZED for both "Not authenticated" and
      // "Invalid or expired token" / "Token has been revoked".
      expect(
        SystemStateSpec.classify(
          statusCode: 401,
          message: 'Invalid or expired token',
        ),
        SystemState.sessionExpired,
      );
      expect(
        SystemStateSpec.classify(
          statusCode: 401,
          message: 'Token has been revoked',
        ),
        SystemState.sessionExpired,
      );
      expect(
        SystemStateSpec.classify(statusCode: 401, message: 'Not authenticated'),
        SystemState.unauthorized,
      );
    });

    test('403 → permission denied; 404/409/422 name their own state', () {
      expect(
        SystemStateSpec.classify(
          statusCode: 403,
          errorCode: 'FORBIDDEN',
          message: 'Access denied',
        ),
        SystemState.permissionDenied,
      );
      expect(
        SystemStateSpec.classify(statusCode: 404, message: 'Not found'),
        SystemState.notFound,
      );
      expect(
        SystemStateSpec.classify(
          statusCode: 409,
          message: 'Phone number already registered. Please login.',
        ),
        SystemState.conflict,
      );
      expect(
        SystemStateSpec.classify(statusCode: 422, message: 'Price is required'),
        SystemState.validation,
      );
      // Only the remaining 4xx are genuinely worth a plain retry.
      expect(
        SystemStateSpec.classify(statusCode: 429, message: 'Too many requests'),
        SystemState.genericRetry,
      );
    });

    test('ApiException.systemState exposes the classification', () {
      expect(
        const ApiException(
          statusCode: 503,
          errorCode: 'SERVICE_UNAVAILABLE',
          message: 'Object storage is unavailable',
        ).systemState,
        SystemState.maintenance,
      );
      expect(
        const ApiException(
          statusCode: 403,
          errorCode: 'FORBIDDEN',
          message: 'Access denied',
        ).systemState,
        SystemState.permissionDenied,
      );
    });

    test('ApiException.fromDioError replaces Dio-speak with state copy', () {
      final offline = ApiException.fromDioError(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.connectionError,
          error: Exception('connection refused'),
        ),
      );
      expect(offline.kind, ApiFailureKind.offline);
      expect(offline.systemState, SystemState.offline);
      // Dio's raw text ("The connection errored: …") never reaches the UI.
      expect(offline.message, SystemStateSpec.of(SystemState.offline).message);

      final timeout = ApiException.fromDioError(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.receiveTimeout,
        ),
      );
      expect(timeout.systemState, SystemState.timeout);
      // The timeout copy is app-owned, never Dio's raw text.
      expect(timeout.message, SystemStateSpec.of(SystemState.timeout).message);

      // A 503 envelope's technical wording becomes the maintenance copy.
      final maintenance = ApiException.fromDioError(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/x'),
            statusCode: 503,
            data: {
              'success': false,
              'message': 'Object storage is unavailable',
              'error_code': 'STORAGE_UNAVAILABLE',
            },
          ),
        ),
      );
      expect(maintenance.systemState, SystemState.maintenance);
      expect(
        maintenance.message,
        SystemStateSpec.of(SystemState.maintenance).message,
      );
    });
  });

  group('SystemStateSpec — the expanded vocabulary', () {
    test('every state has copy, an icon and an action', () {
      for (final state in SystemState.values) {
        final spec = SystemStateSpec.of(state);
        expect(spec.state, state, reason: '$state spec state mismatch');
        expect(spec.title.trim(), isNotEmpty, reason: '$state has no title');
        expect(spec.message.trim(), isNotEmpty, reason: '$state has no copy');
        expect(spec.action, isNotNull, reason: '$state has no action');
      }
    });

    test('transport failures own their copy; server-explained ones do not', () {
      for (final state in {
        SystemState.offline,
        SystemState.networkError,
        SystemState.timeout,
        SystemState.sessionExpired,
        SystemState.unauthorized,
        SystemState.maintenance,
      }) {
        expect(SystemStateSpec.of(state).ownsCopy, isTrue,
            reason: '$state is infrastructure — its copy must be app-owned');
      }
      for (final state in {
        SystemState.notFound,
        SystemState.conflict,
        SystemState.validation,
        SystemState.serverError,
        SystemState.permissionDenied,
      }) {
        expect(SystemStateSpec.of(state).ownsCopy, isFalse,
            reason: '$state usually carries a server explanation worth keeping');
      }
    });

    test('the action matches what actually fixes the failure', () {
      // Retrying helps a timeout and a stale-conflict (after a refresh).
      expect(SystemStateSpec.of(SystemState.timeout).action, SystemAction.retry);
      expect(SystemStateSpec.of(SystemState.conflict).action, SystemAction.retry);
      // Re-sending identical input can never fix these.
      expect(
          SystemStateSpec.of(SystemState.validation).action, SystemAction.none);
      expect(
          SystemStateSpec.of(SystemState.notFound).action, SystemAction.none);
    });

    test('a server-explained conflict/validation keeps the server wording',
        () {
      final conflict = SystemStateSpec.resolve(
        statusCode: 409,
        message: 'Phone number already registered. Please login.',
      );
      expect(conflict.state, SystemState.conflict);
      expect(conflict.message, 'Phone number already registered. Please login.');

      final unexplained = SystemStateSpec.resolve(statusCode: 422);
      expect(unexplained.state, SystemState.validation);
      expect(unexplained.message, SystemStateSpec.of(SystemState.validation).message);
    });
  });

  group('SystemStateSpec.resolve — feature copy is never rewritten', () {
    test('a feature-owned title/message comes through verbatim', () {
      final spec = SystemStateSpec.resolve(
        title: 'Could not load reports',
        message: 'Server down',
        fallbackMessage: 'Something went wrong.',
      );
      expect(spec.state, SystemState.genericRetry);
      expect(spec.title, 'Could not load reports');
      expect(spec.message, 'Server down');
      expect(spec.action, SystemAction.retry);
    });

    test('an infrastructure state owns its copy (never Dio-speak)', () {
      final spec = SystemStateSpec.resolve(
        state: SystemState.offline,
        message: 'Some raw Dio text',
      );
      expect(spec.message, SystemStateSpec.of(SystemState.offline).message);
    });

    test('blank copy falls back to the state default', () {
      final spec = SystemStateSpec.resolve(
        message: '   ',
        fallbackMessage: 'Could not load inventory.',
      );
      expect(spec.message, 'Could not load inventory.');
    });
  });

  group('SystemStateView (widget)', () {
    Widget host(SystemStateView view) => MaterialApp(
          home: Scaffold(body: view),
        );

    testWidgets('offline renders its copy, icon and Retry', (tester) async {
      await tester.pumpWidget(
        host(
          SystemStateView(
            spec: SystemStateSpec.of(SystemState.offline),
            onRetry: () {},
          ),
        ),
      );

      expect(find.text('No internet connection'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('permission denied offers Switch shop, never a lying Retry',
        (tester) async {
      var switched = false;
      await tester.pumpWidget(
        host(
          SystemStateView(
            spec: SystemStateSpec.resolve(
              state: SystemState.permissionDenied,
              title: 'No access to this shop',
              message: 'Access denied',
            ),
            onSwitchShop: () => switched = true,
          ),
        ),
      );

      expect(find.text('No access to this shop'), findsOneWidget);
      expect(find.text('Access denied'), findsOneWidget);
      expect(find.text('Switch shop'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);

      await tester.tap(find.text('Switch shop'));
      expect(switched, isTrue);
    });

    testWidgets('a no-shop view without a callback shows nothing to tap',
        (tester) async {
      await tester.pumpWidget(
        host(
          SystemStateView(
            spec: const SystemStateSpec(
              state: SystemState.empty,
              title: 'No shop selected',
              message: 'Choose a shop to manage its POS integration.',
              icon: Icons.storefront_outlined,
              action: SystemAction.none,
            ),
          ),
        ),
      );

      expect(find.text('No shop selected'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('session expired points at sign-in, not at Retry',
        (tester) async {
      await tester.pumpWidget(
        host(
          SystemStateView(
            spec: SystemStateSpec.of(SystemState.sessionExpired),
            onSignIn: () {},
          ),
        ),
      );

      expect(find.text('Session expired'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('empty state renders the feature copy and its action',
        (tester) async {
      var cleared = false;
      await tester.pumpWidget(
        host(
          SystemStateView.empty(
            title: 'No products match your search',
            icon: Icons.search_off_outlined,
            action: OutlinedButton(
              onPressed: () => cleared = true,
              child: const Text('Clear search'),
            ),
          ),
        ),
      );

      expect(find.text('No products match your search'), findsOneWidget);
      // No message was given → no empty Text line is rendered.
      expect(find.text(''), findsNothing);
      expect(find.text('Clear search'), findsOneWidget);

      await tester.tap(find.text('Clear search'));
      expect(cleared, isTrue);
    });
  });

  group('SystemStateBody (widget)', () {
    testWidgets('loading → failure → content, in that order', (tester) async {
      var retries = 0;

      Widget build({
        required bool isLoading,
        SystemStateSpec? failure,
        required WidgetBuilder builder,
      }) =>
          MaterialApp(
            home: Scaffold(
              body: SystemStateBody(
                isLoading: isLoading,
                failure: failure,
                onRetry: () => retries++,
                builder: builder,
              ),
            ),
          );

      // Loading.
      await tester.pumpWidget(
        build(
          isLoading: true,
          failure: null,
          builder: (_) => const Text('content'),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('content'), findsNothing);

      // Failure — a 500 keeps the server's explanation and adds a Retry.
      await tester.pumpWidget(
        build(
          isLoading: false,
          failure: SystemStateSpec.resolve(message: 'Server exploded'),
          builder: (_) => const Text('content'),
        ),
      );
      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('Server exploded'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      expect(retries, 1);
    });

    testWidgets('empty renders the empty copy, not the content',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SystemStateBody(
              isLoading: false,
              failure: null,
              isEmpty: true,
              emptyTitle: 'No products yet',
              emptyMessage: 'Add products or import them from Excel first.',
              onRetry: () {},
              builder: (_) => const Text('content'),
            ),
          ),
        ),
      );

      expect(find.text('No products yet'), findsOneWidget);
      expect(
        find.text('Add products or import them from Excel first.'),
        findsOneWidget,
      );
      expect(find.text('content'), findsNothing);
    });
  });
}