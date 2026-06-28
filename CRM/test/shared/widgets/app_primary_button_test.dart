import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crm/shared/widgets/app_primary_button.dart';

void main() {
  // Regression guard: a solid [backgroundColor] that is light (e.g. okYellow
  // gold in dark mode) must get a dark, legible label — not the near-white
  // accent default, which fails contrast on a light fill.
  testWidgets('light backgroundColor gets a dark label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppPrimaryButton(
            text: 'Freeze',
            backgroundColor: const Color(0xFFDBA13F), // bright gold
            onPressed: () {},
          ),
        ),
      ),
    );

    final label = tester.widget<Text>(find.text('Freeze'));
    expect(label.style?.color?.computeLuminance(), lessThan(0.1));
  });

  testWidgets('default gradient gets a near-white label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppPrimaryButton(text: 'Go', onPressed: () {}),
        ),
      ),
    );

    final label = tester.widget<Text>(find.text('Go'));
    expect(label.style?.color?.computeLuminance(), greaterThan(0.5));
  });
}
