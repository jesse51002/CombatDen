import 'package:flutter_test/flutter_test.dart';

import 'package:app_management/main.dart';

void main() {
  testWidgets('Renders placeholder screen', (WidgetTester tester) async {
    await tester.pumpWidget(const AppManagementRoot());
    expect(find.text('AppManagement'), findsOneWidget);
  });
}
