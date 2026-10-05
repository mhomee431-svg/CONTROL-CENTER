import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/network/api_error_handler.dart';
import 'package:hyperlocal_app/core/widgets/state_view_builder.dart';
import 'package:hyperlocal_app/core/widgets/skeletons.dart';

void main() {
  Widget buildTestWidget({
    required bool isLoading,
    required ApiException? error,
    required List<String>? data,
    VoidCallback? onRetry,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: StateViewBuilder<String>(
          isLoading: isLoading,
          error: error,
          data: data,
          onRetry: onRetry ?? () {},
          onSuccess: (context, items) => ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) =>
                ListTile(title: Text(items[index])),
          ),
        ),
      ),
    );
  }

  testWidgets('shows list row placeholders when isLoading is true', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildTestWidget(isLoading: true, error: null, data: null),
    );
    // A list of [T] is arriving, so the placeholder is a list of rows. This
    // used to assert a centred CircularProgressIndicator plus the text
    // "Loading details...", which said nothing about what was coming.
    expect(find.byType(SkeletonList), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('shows error view when error is present', (tester) async {
    await tester.pumpWidget(
      buildTestWidget(
        isLoading: false,
        error: const ApiException(
          type: ApiErrorType.offline,
          message: 'No internet connection detected. Please connect to Wi-Fi or mobile data.',
        ),
        data: null,
      ),
    );

    expect(find.text('No Internet Connection'), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);
  });

  testWidgets('shows empty state when data is empty', (tester) async {
    await tester.pumpWidget(
      buildTestWidget(isLoading: false, error: null, data: []),
    );

    expect(find.text('No Items Found'), findsOneWidget);
    expect(
      find.text('There are no items available right now.'),
      findsOneWidget,
    );
    expect(find.text('Refresh'), findsOneWidget);
  });

  testWidgets('shows success content when data is present', (tester) async {
    await tester.pumpWidget(
      buildTestWidget(
        isLoading: false,
        error: null,
        data: const ['Item 1', 'Item 2'],
      ),
    );

    expect(find.text('Item 1'), findsOneWidget);
    expect(find.text('Item 2'), findsOneWidget);
  });

  testWidgets('retry button triggers onRetry callback', (tester) async {
    var retryCount = 0;
    await tester.pumpWidget(
      buildTestWidget(
        isLoading: false,
        error: const ApiException(
          type: ApiErrorType.serverError,
          message:
              'Server error encountered (500). Our team has been notified.',
        ),
        data: null,
        onRetry: () => retryCount++,
      ),
    );

    await tester.tap(find.text('Try Again'));
    expect(retryCount, equals(1));
  });

  testWidgets('shows timeout error view for timeout errors', (tester) async {
    await tester.pumpWidget(
      buildTestWidget(
        isLoading: false,
        error: const ApiException(
          type: ApiErrorType.timeout,
          message: 'Connection timed out. Please check your internet connection and try again.',
        ),
        data: null,
      ),
    );

    expect(find.text('Request Timed Out'), findsOneWidget);
  });
}
