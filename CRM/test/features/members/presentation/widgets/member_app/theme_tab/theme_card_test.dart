import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/members/presentation/widgets/member_app/theme_tab/theme_card.dart';
import 'package:theme_flutter/data/models/customization_style.dart';

// The card's four states are the whole point of this widget: "live for
// members" (saved) and "showing on the phone right now" (previewing) are
// DIFFERENT things, and conflating them is what made a founder believe his
// theme was already applied when nothing had been saved.
const ThemeStyle _style = ThemeStyle(
  id: 'ApexMMA',
  displayName: 'Apex MMA',
  celebrationImageUrl: '', // empty → placeholder, no network image in tests
  category: 'Fighting',
);

Future<void> _pumpCard(
  WidgetTester tester, {
  required bool isSaved,
  required bool isPreviewing,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ThemeCard(
          style: _style,
          isSaved: isSaved,
          isPreviewing: isPreviewing,
        ),
      ),
    ),
  );
}

BoxDecoration _decoration(WidgetTester tester) {
  final container = tester.widget<Container>(
    find
        .descendant(
          of: find.byType(ThemeCard),
          matching: find.byType(Container),
        )
        .first,
  );
  return container.decoration! as BoxDecoration;
}

/// The card's own root [Semantics] annotation (the outermost one inside the
/// card, before the ink well and the icons add theirs).
SemanticsProperties _rootSemantics(WidgetTester tester) {
  return tester
      .widget<Semantics>(
        find
            .descendant(
              of: find.byType(ThemeCard),
              matching: find.byType(Semantics),
            )
            .first,
      )
      .properties;
}

void main() {
  group('ThemeCard state matrix', () {
    testWidgets('saved + previewing: check, heavy border, both words', (
      tester,
    ) async {
      await _pumpCard(tester, isSaved: true, isPreviewing: true);

      expect(find.text('Live for members · previewing'), findsOneWidget);
      expect(find.byIcon(Symbols.check_circle_sharp), findsOneWidget);
      expect(find.byIcon(Symbols.visibility_sharp), findsNothing);

      final decoration = _decoration(tester);
      expect(decoration.color, DesignConstants.card);
      final border = decoration.border! as Border;
      expect(border.top.color, DesignConstants.primaryColor);
      expect(border.top.width, DesignConstants.buttonBorderSize);
    });

    testWidgets('saved, not previewing: still the ONLY checkmarked state', (
      tester,
    ) async {
      await _pumpCard(tester, isSaved: true, isPreviewing: false);

      expect(find.text('Live for members'), findsOneWidget);
      expect(find.text('Live for members · previewing'), findsNothing);
      expect(find.byIcon(Symbols.check_circle_sharp), findsOneWidget);
      expect(find.byIcon(Symbols.visibility_sharp), findsNothing);

      final decoration = _decoration(tester);
      expect(decoration.color, DesignConstants.card);
      final border = decoration.border! as Border;
      expect(border.top.color, DesignConstants.primaryColor);
      expect(border.top.width, DesignConstants.buttonBorderSize);
    });

    testWidgets('previewing, not saved: eye + tint + hairline, NO check', (
      tester,
    ) async {
      await _pumpCard(tester, isSaved: false, isPreviewing: true);

      expect(find.text('Previewing only'), findsOneWidget);
      expect(find.byIcon(Symbols.visibility_sharp), findsOneWidget);
      // The load-bearing assertion: a previewed-but-unsaved theme must NEVER
      // wear the "this is your app theme" checkmark.
      expect(find.byIcon(Symbols.check_circle_sharp), findsNothing);

      final decoration = _decoration(tester);
      expect(decoration.color, DesignConstants.primaryColor10);
      final border = decoration.border! as Border;
      expect(border.top.color, DesignConstants.line);
      expect(border.top.width, DesignConstants.dividerThickness);
    });

    testWidgets('neither: plain card, no marker, no sub-label', (tester) async {
      await _pumpCard(tester, isSaved: false, isPreviewing: false);

      expect(find.text('Apex MMA'), findsOneWidget);
      expect(find.text('Live for members'), findsNothing);
      expect(find.text('Previewing only'), findsNothing);
      expect(find.byIcon(Symbols.check_circle_sharp), findsNothing);
      expect(find.byIcon(Symbols.visibility_sharp), findsNothing);

      final decoration = _decoration(tester);
      expect(decoration.color, DesignConstants.card);
      expect(decoration.border, isNull);
    });

    testWidgets('the row is a focusable button, selected only when saved', (
      tester,
    ) async {
      await _pumpCard(tester, isSaved: true, isPreviewing: false);
      // InkWell (not GestureDetector) so the row takes keyboard focus and
      // paints a focus ring, matching the pane's chips and arrows.
      expect(find.byType(InkWell), findsOneWidget);
      expect(_rootSemantics(tester).button, isTrue);
      expect(_rootSemantics(tester).selected, isTrue);

      await _pumpCard(tester, isSaved: false, isPreviewing: true);
      // "Selected" tracks SAVED, not previewing.
      expect(_rootSemantics(tester).selected, isFalse);
    });
  });
}
