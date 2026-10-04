import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/network/api_error_handler.dart';
import 'package:hyperlocal_app/core/widgets/error_state.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ErrorState', () {
    testWidgets('shows the screen-specific headline and a retry', (tester) async {
      await tester.pumpWidget(
        _host(
          ErrorState.from(
            const ApiException(
              type: ApiErrorType.serverError,
              message: 'Something went wrong on our side.',
            ),
            title: 'Unable to load nearby shops',
            onRetry: () {},
          ),
        ),
      );

      expect(find.text('Unable to load nearby shops'), findsOneWidget);
      expect(find.text('Something went wrong on our side.'), findsOneWidget);
      expect(find.byType(RetryButton), findsOneWidget);
    });

    testWidgets('never renders the raw exception', (tester) async {
      // The bug this locks: `Text('Error: $error')` and `message: '$err'`
      // printed the exception itself. `ApiException.toString()` carries the
      // type, the message AND the status code.
      const leaky = ApiException(
        type: ApiErrorType.serverError,
        message: 'Internal failure',
        statusCode: 500,
      );

      await tester.pumpWidget(
        _host(ErrorState.from(leaky, title: 'Unable to load', onRetry: () {})),
      );

      expect(find.textContaining('ApiException'), findsNothing);
      expect(find.textContaining('Status Code'), findsNothing);
      expect(find.textContaining('500'), findsNothing);
      expect(find.text('Internal failure'), findsOneWidget);
    });

    testWidgets('an unrecognised error collapses to safe generic copy', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          ErrorState.from(
            StateError('socket closed at /api/v1/internal/secret'),
            title: 'Unable to load nearby shops',
            onRetry: () {},
          ),
        ),
      );

      // The StateError's own text — including the internal path — must not
      // reach the customer.
      expect(find.textContaining('secret'), findsNothing);
      expect(find.textContaining('socket'), findsNothing);
      expect(
        find.text(
          'Something went wrong. Please check your connection and try again.',
        ),
        findsOneWidget,
      );
    });

    group('no dead retry', () {
      // A retry that cannot succeed is the dead control the app's error rules
      // forbid: the customer taps it, nothing changes, and they conclude the
      // app is broken.
      for (final type in [
        ApiErrorType.accessDenied,
        ApiErrorType.notFound,
        ApiErrorType.conflict,
        ApiErrorType.validation,
        ApiErrorType.rateLimited,
        ApiErrorType.requestCancelled,
      ]) {
        testWidgets('${type.name} offers no retry even if one is passed', (
          tester,
        ) async {
          await tester.pumpWidget(
            _host(
              ErrorState.fromApi(
                ApiException(type: type, message: 'nope'),
                title: 'Unable to load nearby shops',
                // Deliberately passed: the widget must suppress it.
                onRetry: () {},
              ),
            ),
          );

          expect(find.byType(RetryButton), findsNothing);
        });
      }

      for (final type in [
        ApiErrorType.offline,
        ApiErrorType.timeout,
        ApiErrorType.serverError,
        ApiErrorType.partialFailure,
      ]) {
        testWidgets('${type.name} keeps the retry', (tester) async {
          await tester.pumpWidget(
            _host(
              ErrorState.fromApi(
                ApiException(type: type, message: 'nope'),
                title: 'Unable to load nearby shops',
                onRetry: () {},
              ),
            ),
          );

          expect(find.byType(RetryButton), findsOneWidget);
        });
      }

      testWidgets('the retry actually re-runs the failed request', (
        tester,
      ) async {
        var retried = 0;
        await tester.pumpWidget(
          _host(
            ErrorState.fromApi(
              const ApiException(
                type: ApiErrorType.offline,
                message: 'You are offline.',
              ),
              title: 'Unable to load nearby shops',
              onRetry: () => retried++,
            ),
          ),
        );

        await tester.tap(find.byType(RetryButton));
        expect(retried, 1);
      });

      testWidgets('a null retry renders no button at all', (tester) async {
        await tester.pumpWidget(
          _host(ErrorState.fromApi(null, title: 'Unable to load')),
        );

        expect(find.byType(RetryButton), findsNothing);
      });
    });

    testWidgets('each failure kind gets its own icon', (tester) async {
      // One failure must look the same everywhere, so an offline error cannot
      // be a generic "!" on one screen and a wifi-off icon on another.
      Future<IconData> iconFor(ApiErrorType type) async {
        await tester.pumpWidget(
          _host(
            ErrorState.fromApi(
              ApiException(type: type, message: 'x'),
              title: 'Unable to load',
            ),
          ),
        );
        final icon = tester.widget<Icon>(find.byType(Icon).first);
        return icon.icon ?? Icons.error_outline;
      }

      expect(await iconFor(ApiErrorType.offline), Icons.wifi_off_rounded);
      expect(await iconFor(ApiErrorType.notFound), Icons.search_off_rounded);
      expect(
        await iconFor(ApiErrorType.partialFailure),
        Icons.report_gmailerrorred_rounded,
      );
      expect(await iconFor(ApiErrorType.serverError), Icons.cloud_off_rounded);
    });
  });

  group('RetryButton', () {
    testWidgets('is reachable and fires', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(RetryButton(onPressed: () => taps++, label: 'Try again')),
      );

      expect(find.text('Try again'), findsOneWidget);
      await tester.tap(find.byType(RetryButton));
      expect(taps, 1);
    });

    testWidgets('meets the 48px minimum tap height', (tester) async {
      // A frustrated, often one-handed customer must be able to hit it.
      await tester.pumpWidget(_host(RetryButton(onPressed: () {})));

      final size = tester.getSize(find.byType(RetryButton));
      expect(size.height, greaterThanOrEqualTo(48));
    });
  });
}