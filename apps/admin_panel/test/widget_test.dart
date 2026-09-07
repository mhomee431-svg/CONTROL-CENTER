import 'package:flutter_test/flutter_test.dart';

import 'package:hyperlocal_admin_panel/main.dart';

void main() {
  testWidgets('admin shell renders', (WidgetTester tester) async {
    await tester.pumpWidget(const HyperlocalAdminApp());
    expect(find.text('Hyperlocal Admin'), findsWidgets);
  });
}
