import 'package:flutter_test/flutter_test.dart';

import 'helpers/home_layout_host.dart';

import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/formats/layout_formats.dart';
import 'package:mobile_app/features/home/presentation/layouts/home_layout_data.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_item/class_item_thumb.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_item/class_item_time.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_list_item.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_schedule_title.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/date_row.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/date_tab.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/day_class_group.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/schedule_status.dart';
import 'package:mobile_app/features/home/presentation/widgets/upcoming_sessions/upcoming_sessions_card.dart';
import 'package:mobile_app/shared/widgets/nav/app_bottom_nav_bar.dart';
import 'package:mobile_app/shared/widgets/nav/app_nav_item.dart';
import 'package:mobile_app/shared/widgets/topbar/app_topbar.dart';

/// The functional-equivalence gate for `home_format`.
///
/// A layout format may change ARRANGEMENT ONLY. This asserts it
/// mechanically: every value of the enum is pumped, in every state the
/// schedule can be in, and its element set is compared against the
/// contract below. A generated layout that drops a class thumbnail,
/// loses the date rail, or quietly stops opening class detail fails here
/// rather than in review.
///
/// Everything is pumped at a real phone size (390x844 @3x). At the
/// default 800x600 test surface a cramped row still fits, so an
/// arrangement that overflows on an actual device would pass unnoticed.
void main() {
  /// The element set the shipped screen renders, asserted against every
  /// format. Scoped to the FIRST class row so a count is a count of that
  /// row's parts, not of everything the viewport happens to hold.
  void expectClassRowComplete({required bool booked}) {
    final row = find.byType(ClassListItem).first;

    Finder inRow(Finder matching) =>
        find.descendant(of: row, matching: matching);

    // Title, time, instructor.
    expect(inRow(find.text(kTestClasses.first.name)), findsOneWidget);
    expect(inRow(find.byType(ClassItemTime)), findsOneWidget);
    expect(
      inRow(find.text(kTestClasses.first.instructorName)),
      findsOneWidget,
    );

    // The attendee count, and the class image.
    expect(inRow(find.textContaining('attending')), findsOneWidget);
    expect(inRow(find.byType(ClassItemThumb)), findsOneWidget);

    // The booked mark rides the booked page only — that is the state
    // split between home's two pages, and no format may move it.
    expect(
      inRow(find.text('You booked this class!')),
      booked ? findsOneWidget : findsNothing,
    );
  }

  group('every home format renders the full loaded screen', () {
    for (final format in HomeFormat.values) {
      for (final booked in [false, true]) {
        testWidgets('$format / booked=$booked', (tester) async {
          phoneSized(tester);
          await tester.pumpWidget(
            homeHost(
              format: format,
              data: HomeLayoutData(classes: kTestClasses, booked: booked),
            ),
          );

          // Chrome.
          expect(find.byType(AppTopbar), findsOneWidget);
          expect(find.byType(AppBottomNavBar), findsOneWidget);
          expect(find.byType(AppNavItem), findsNWidgets(4));

          // The booked page's own two pieces.
          expect(
            find.byType(UpcomingSessionsCard),
            booked ? findsOneWidget : findsNothing,
          );
          expect(
            find.byType(ClassScheduleTitle),
            booked ? findsOneWidget : findsNothing,
          );

          // The date rail, and the days hanging off it.
          expect(find.byType(DateRow), findsOneWidget);
          expect(find.byType(DateTab), findsWidgets);
          expect(find.byType(DayClassGroup), findsWidgets);
          expect(find.byType(ClassListItem), findsWidgets);

          // A loaded, non-empty schedule shows NO status — the status is
          // what stands in for the day list, never something beside it.
          expect(find.byType(ScheduleStatus), findsNothing);

          expectClassRowComplete(booked: booked);
        });
      }
    }
  });

  group('every home format shows the status in place of the day list', () {
    final states = <String, HomeLayoutData>{
      'loading': const HomeLayoutData(classes: null, booked: true),
      'error': const HomeLayoutData(
        classes: null,
        booked: true,
        hasError: true,
      ),
      'empty': const HomeLayoutData(classes: [], booked: true),
    };

    for (final format in HomeFormat.values) {
      for (final entry in states.entries) {
        testWidgets('$format / ${entry.key}', (tester) async {
          phoneSized(tester);
          await tester.pumpWidget(
            homeHost(format: format, data: entry.value),
          );

          expect(find.byType(ScheduleStatus), findsOneWidget);
          expect(find.byType(DayClassGroup), findsNothing);
          expect(find.byType(ClassListItem), findsNothing);

          // Everything around the schedule survives the empty state.
          expect(find.byType(AppTopbar), findsOneWidget);
          expect(find.byType(UpcomingSessionsCard), findsOneWidget);
          expect(find.byType(ClassScheduleTitle), findsOneWidget);
          expect(find.byType(DateRow), findsOneWidget);
          expect(find.byType(DateTab), findsWidgets);
          expect(find.byType(AppNavItem), findsNWidgets(4));
        });
      }
    }
  });

  group('every home format keeps the date rail tappable', () {
    for (final format in HomeFormat.values) {
      testWidgets('$format', (tester) async {
        phoneSized(tester);
        await tester.pumpWidget(
          homeHost(
            format: format,
            data: const HomeLayoutData(classes: kTestClasses, booked: true),
          ),
        );

        final tabs = tester.widgetList<DateTab>(find.byType(DateTab));
        expect(tabs.length, greaterThan(1));
        // Exactly one day reads as selected, and today leads the rail.
        expect(tabs.where((t) => t.isSelected).length, 1);
        expect(tabs.first.label, 'Today');
      });
    }
  });

  group('every home format opens class detail from a class row', () {
    for (final format in HomeFormat.values) {
      testWidgets('$format', (tester) async {
        phoneSized(tester);
        final pushed = <String>[];
        await tester.pumpWidget(
          homeHost(
            format: format,
            data: const HomeLayoutData(classes: kTestClasses, booked: true),
            pushed: pushed,
          ),
        );

        // The header is most of a phone screen, so the first row starts
        // below the fold in several formats. Scroll it into view before
        // tapping — an off-screen tap proves nothing.
        await tester.ensureVisible(find.byType(ClassListItem).first);
        await tester.pumpAndSettle();
        await tester.tap(find.byType(ClassListItem).first);
        // The schedule's demo double-tap shortcut keeps the gesture
        // arena open until the double-tap window closes, so a row's own
        // tap only resolves after it.
        await tester.pump(const Duration(milliseconds: 400));

        expect(pushed, contains(AppRoutes.classDetail));
      });
    }
  });
}
