import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/features/shell/offline_banner.dart';

void main() {
  testWidgets('OfflineBanner shows the offline notice when disconnected', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: OfflineBanner(isConnected: false)),
      ),
    );

    expect(
      find.text("You're offline — some content may be unavailable"),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.wifi_off), findsOneWidget);
  });

  testWidgets('OfflineBanner renders nothing while connected', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: OfflineBanner(isConnected: true))),
    );

    expect(
      find.text("You're offline — some content may be unavailable"),
      findsNothing,
    );
    expect(find.byIcon(Icons.wifi_off), findsNothing);
  });
}
