import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/member_details/presentation/dialogs/freeze/months_stepper.dart';

void main() {
  Widget host(Widget child) =>
      MaterialApp(home: Scaffold(body: child));

  testWidgets(
    'renders the duration, suffix, bounds hint, and current value',
    (tester) async {
      final controller = TextEditingController(text: '3');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        host(
          MonthsStepper(
            controller: controller,
            minMonths: 1,
            maxMonths: 12,
            onDecrement: () {},
            onIncrement: () {},
            onChanged: () {},
          ),
        ),
      );

      expect(find.text('Freeze duration'), findsOneWidget);
      expect(find.text('months'), findsOneWidget);
      expect(find.text('Between 1 and 12 months.'), findsOneWidget);
      // The current value comes from the controller, rendered in
      // the field.
      expect(find.text('3'), findsOneWidget);
    },
  );

  testWidgets(
    'the two step buttons fire decrement (left) and increment (right)',
    (tester) async {
      final controller = TextEditingController(text: '1');
      addTearDown(controller.dispose);
      var increments = 0;
      var decrements = 0;

      await tester.pumpWidget(
        host(
          MonthsStepper(
            controller: controller,
            minMonths: 1,
            maxMonths: 12,
            onDecrement: () => decrements++,
            onIncrement: () => increments++,
            onChanged: () {},
          ),
        ),
      );

      // Layout is [- button] [field] [+ button] — exactly two.
      final stepButtons = find.byType(OutlinedButton);
      expect(stepButtons, findsNWidgets(2));

      await tester.tap(stepButtons.last); // increment
      await tester.tap(stepButtons.first); // decrement
      await tester.pump();

      expect(increments, 1);
      expect(decrements, 1);
    },
  );
}
