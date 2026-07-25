import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_dob_field.dart';

/// **An UNTOUCHED wheel may not commit a date of birth.**
///
/// The sheet has to open the wheel somewhere, and with no value yet that
/// somewhere is today. A Done that committed the opening position would write
/// today's date into a member's record on a tap that chose nothing — a wrong
/// value nothing on screen ever states afterwards, so nobody would think to
/// correct it. This suite is the guard that Done stays inert until the wheel
/// actually reports a date, and that Clear remains the way to say "no date".
void main() {
  /// The field wired to a value that lives outside it, like the real details
  /// step's — so what a tap COMMITS is observed rather than inferred.
  ///
  /// Returns the list of every value the field reported, in order (a Clear
  /// reports null).
  Future<List<DateTime?>> pumpField(
    WidgetTester tester, {
    DateTime? initial,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1180, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final changes = <DateTime?>[];
    DateTime? value = initial;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => KioskDobField(
              value: value,
              onChanged: (picked) {
                changes.add(picked);
                setState(() => value = picked);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return changes;
  }

  /// Opens the sheet by its own box — the calendar glyph is inside the tappable
  /// area in both the empty and the filled state.
  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byIcon(Symbols.calendar_month_sharp));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoDatePicker), findsOneWidget);
  }

  Finder doneButton() => find.widgetWithText(KioskPrimaryButton, 'Done');

  KioskPrimaryButton done(WidgetTester tester) =>
      tester.widget<KioskPrimaryButton>(doneButton());

  testWidgets('Done is inert until the wheel reports a date, and pressing it '
      'commits nothing', (tester) async {
    final changes = await pumpField(tester);
    await openSheet(tester);

    // Nothing has been chosen, so there is nothing to commit.
    expect(done(tester).onPressed, isNull);

    await tester.tap(doneButton());
    await tester.pumpAndSettle();

    // No value written and the sheet is still up: the member has not been
    // silently given today's date as their date of birth.
    expect(changes, isEmpty);
    expect(find.byType(CupertinoDatePicker), findsOneWidget);
    expect(find.text('MM / DD / YYYY'), findsOneWidget);
  });

  testWidgets('turning the wheel releases Done, and Done commits that date',
      (tester) async {
    final changes = await pumpField(tester);
    final today = DateTime.now();

    await openSheet(tester);
    // The YEAR column, dragged toward earlier years — every result is inside
    // the wheel's own range, so the turn always lands on a real date.
    await tester.drag(find.text('${today.year}'), const Offset(0, 70));
    await tester.pumpAndSettle();

    expect(done(tester).onPressed, isNotNull);
    await tester.tap(doneButton());
    await tester.pumpAndSettle();

    expect(changes, hasLength(1));
    final picked = changes.single;
    expect(picked, isNotNull);
    // The committed date is the one the wheel reported, never the opening
    // position it was seeded with.
    expect(picked!.year, lessThan(today.year));
    // And the box reads it back.
    expect(find.text(KioskDobField.display(picked)), findsOneWidget);
  });

  testWidgets('a date already held is what Done re-commits, no turn needed',
      (tester) async {
    final held = DateTime(1994, 3, 7);
    final changes = await pumpField(tester, initial: held);
    await openSheet(tester);

    // A field that already holds a date has something to commit from the first
    // frame — the guard blocks a phantom value, never a real one.
    expect(done(tester).onPressed, isNotNull);
    await tester.tap(doneButton());
    await tester.pumpAndSettle();

    expect(changes, [held]);
  });

  testWidgets('Clear is how "no date" is said, and it is live untouched',
      (tester) async {
    final changes = await pumpField(tester, initial: DateTime(1994, 3, 7));
    await openSheet(tester);

    await tester.tap(find.widgetWithText(KioskOutlineButton, 'Clear'));
    await tester.pumpAndSettle();

    // An explicit null — the answer an untouched wheel can never give.
    expect(changes, [null]);
    expect(find.text('MM / DD / YYYY'), findsOneWidget);
    expect(find.byType(CupertinoDatePicker), findsNothing);
  });
}
