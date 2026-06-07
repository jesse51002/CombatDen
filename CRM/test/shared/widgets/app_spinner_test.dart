import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crm/shared/widgets/app_spinner.dart';

void main() {
  testWidgets('builds and paints the sweep without exception',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: AppSpinner())),
      ),
    );
    // One mid-cycle frame; never pumpAndSettle (it repeats forever).
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.takeException(), isNull);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('reduced motion renders a static arc and settles',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Center(child: AppSpinner()),
          ),
        ),
      ),
    );
    // Would time out if the controller kept repeating under reduced motion.
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
