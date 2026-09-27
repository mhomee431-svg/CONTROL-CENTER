import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/network/connectivity_service.dart';
import 'package:hyperlocal_app/features/shell/offline_banner.dart';

void main() {
  Widget host(ConnectivityStatus status, {VoidCallback? onRetry}) => MaterialApp(
    home: Scaffold(
      body: OfflineBanner(status: status, onRetry: onRetry),
    ),
  );

  testWidgets('renders nothing while online', (tester) async {
    await tester.pumpWidget(host(ConnectivityStatus.online));

    // Online is the quiet default: the banner must cost no layout at all.
    expect(find.byKey(const Key('offlineBannerMessage')), findsNothing);
    expect(find.byType(OfflineBanner), findsOneWidget);
  });

  testWidgets('offline shows a clear status and a retry action', (tester) async {
    var retried = 0;
    await tester.pumpWidget(
      host(ConnectivityStatus.offline, onRetry: () => retried++),
    );

    expect(
      find.text("You're offline — some content may be unavailable"),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.wifi_off), findsOneWidget);

    // Retry must be reachable: the spec forbids trapping the customer.
    expect(find.byKey(const Key('offlineBannerRetry')), findsOneWidget);
    await tester.tap(find.byKey(const Key('offlineBannerRetry')));
    expect(retried, 1);
  });

  testWidgets('reconnecting says so rather than claiming to be online', (
    tester,
  ) async {
    await tester.pumpWidget(host(ConnectivityStatus.reconnecting));

    // The honest middle state. Reporting "online" here would be the exact
    // failure the tri-state exists to prevent.
    expect(find.text('Reconnecting…'), findsOneWidget);
    expect(find.textContaining("You're offline"), findsNothing);
    // A spinner, not a scary error icon.
    expect(find.byIcon(Icons.wifi_off), findsNothing);
  });

  testWidgets('retry is omitted when no handler is supplied', (tester) async {
    await tester.pumpWidget(host(ConnectivityStatus.offline));

    // A disabled-looking retry that does nothing is worse than none.
    expect(find.byKey(const Key('offlineBannerRetry')), findsNothing);
    expect(find.text("You're offline — some content may be unavailable"),
        findsOneWidget);
  });
}