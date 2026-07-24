import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/rewards/presentation/widgets/value_badge_field.dart';

void main() {
  Widget host(TextEditingController controller) => MaterialApp(
        home: Scaffold(body: ValueBadgeField(controller: controller)),
      );

  /// The fill of the chip carrying [label] — sapphire when it is the active
  /// preset, the neutral card fill otherwise.
  Color chipFill(WidgetTester tester, String label) {
    final container = tester.widget<Container>(
      find
          .ancestor(of: find.text(label), matching: find.byType(Container))
          .first,
    );
    return (container.decoration! as BoxDecoration).color!;
  }

  group('valueBadgePresetIndex', () {
    test('matches a preset exactly', () {
      expect(valueBadgePresetIndex('Free'), 0);
      expect(valueBadgePresetIndex('10% off'), 1);
      expect(valueBadgePresetIndex('25% off'), 2);
      expect(valueBadgePresetIndex('50% off'), 3);
    });

    test('matches trimmed and case-insensitively', () {
      expect(valueBadgePresetIndex('  free '), 0);
      expect(valueBadgePresetIndex('25% OFF'), 2);
    });

    test('returns -1 for a custom or empty badge', () {
      expect(valueBadgePresetIndex('1 week'), -1);
      expect(valueBadgePresetIndex('BOGO'), -1);
      expect(valueBadgePresetIndex(''), -1);
      expect(valueBadgePresetIndex('   '), -1);
    });
  });

  testWidgets('renders the label, every preset chip, and the helper text',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(host(controller));

    expect(find.text('Value badge'), findsOneWidget);
    for (final preset in kValueBadgePresets) {
      expect(find.text(preset), findsOneWidget);
    }
    expect(
      find.text('e.g. Free, 25% off. Max 16 characters.'),
      findsOneWidget,
    );
  });

  testWidgets('tapping a chip fills the field with that badge',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(host(controller));
    await tester.tap(find.text('25% off'));
    await tester.pump();

    expect(controller.text, '25% off');
    // The caret lands after the inserted text, so typing extends it.
    expect(controller.selection.baseOffset, '25% off'.length);
  });

  testWidgets('tapping a second chip replaces the first badge',
      (tester) async {
    final controller = TextEditingController(text: 'Free');
    addTearDown(controller.dispose);

    await tester.pumpWidget(host(controller));
    await tester.tap(find.text('50% off'));
    await tester.pump();

    expect(controller.text, '50% off');
  });

  testWidgets('the field stays freely editable for a custom badge',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(host(controller));
    await tester.enterText(find.byType(TextFormField), '1 week');
    await tester.pump();

    expect(controller.text, '1 week');
    // A custom badge lights no chip.
    for (final preset in kValueBadgePresets) {
      expect(chipFill(tester, preset), DesignConstants.card);
    }
  });

  testWidgets('a chip pick can still be typed over', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(host(controller));
    await tester.tap(find.text('Free'));
    await tester.pump();
    await tester.enterText(find.byType(TextFormField), 'BOGO');
    await tester.pump();

    expect(controller.text, 'BOGO');
  });

  testWidgets('the 16-character limit holds', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(host(controller));
    await tester.enterText(
      find.byType(TextFormField),
      'Post-workout recovery drink',
    );
    await tester.pump();

    expect(kValueBadgeMaxLength, 16);
    expect(controller.text.length, kValueBadgeMaxLength);
    expect(controller.text, 'Post-workout rec');
  });

  testWidgets('the active chip reflects the current text', (tester) async {
    final controller = TextEditingController(text: '25% off');
    addTearDown(controller.dispose);

    await tester.pumpWidget(host(controller));

    expect(chipFill(tester, '25% off'), DesignConstants.primaryColor);
    expect(chipFill(tester, 'Free'), DesignConstants.card);

    // Typing over it moves the lit chip with the text.
    await tester.enterText(find.byType(TextFormField), 'Free');
    await tester.pump();

    expect(chipFill(tester, 'Free'), DesignConstants.primaryColor);
    expect(chipFill(tester, '25% off'), DesignConstants.card);
  });

  testWidgets('an empty badge fails validation', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final formKey = GlobalKey<FormState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            key: formKey,
            child: ValueBadgeField(controller: controller),
          ),
        ),
      ),
    );

    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('A value badge is required.'), findsOneWidget);

    controller.text = 'Free';
    await tester.pump();
    expect(formKey.currentState!.validate(), isTrue);
  });
}
