import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/stub_asset_bundle.dart';

import 'package:mobile_app/core/formats/layout_formats.dart';
import 'package:mobile_app/features/class_booking/presentation/layouts/parts/class_tab_bar.dart';
import 'package:mobile_app/features/class_booking/presentation/screens/class_screen.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_details_section.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_image_banner.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_instructor_section.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_location_section.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_meta_section.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_reserve_footer.dart';
import 'package:mobile_app/features/home/data/mock_class_schedule.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';
import 'package:mobile_app/shared/widgets/topbar/app_topbar.dart';
import 'package:mobile_app/shared/widgets/topbar/parts/topbar_back_button.dart';

/// The functional-equivalence gate for `class_format`.
///
/// A layout format may change ARRANGEMENT ONLY. This asserts it
/// mechanically: every value of the enum is pumped at real phone size
/// and its element set is compared against the contract below. A
/// generated layout that drops the location section, hides the back
/// control, or adds a second "Reserve" button for convenience fails
/// here rather than in review.
///
/// The second contract this screen carries is its ONE commit point.
/// Reserving is the only irreversible thing on the screen, so the count
/// of reserve actions is asserted rather than their presence — and it
/// is counted through the whole tree, so a duplicate parked behind a
/// tab counts too.
///
/// The third is the set of hooks the dev capture harness
/// (`tools/capture/`) drives — the body scroll controller, a key around
/// the class photo, a key around the reserve CTA — plus the horizontal
/// swipe into the post-class flow. None of them is visible, so nothing
/// but a test notices when an arrangement quietly drops one.
const MockClass _sample = MockClass(
  name: 'Muay Thai Sparring',
  timeRange: '6:00pm - 6:55pm',
  durationMinutes: 55,
  mentor: 'Coach Ana',
  imageUrl: 'https://example.test/class.jpg',
  description: 'Six rounds on the pads, then live rounds with the team.',
  instructorBio: 'Ten years cornering fighters at the national level.',
  instructorImageUrl: 'https://example.test/coach.jpg',
  attending: 12,
);

const List<String> _kTabLabels = ['Details', 'Instructor', 'Location'];

typedef _Hooks = ({
  ScrollController controller,
  GlobalKey imageKey,
  GlobalKey reserveKey,
});

void main() {
  /// Pump at a real phone size. At the default 800x600 test surface a
  /// cramped arrangement still fits, so a layout that overflows on an
  /// actual device would pass unnoticed.
  void phoneSized(WidgetTester tester) {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  _Hooks makeHooks() {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    return (
      controller: controller,
      imageKey: GlobalKey(),
      reserveKey: GlobalKey(),
    );
  }

  Future<_Hooks> pump(WidgetTester tester, ClassFormat format) async {
    phoneSized(tester);
    final hooks = makeHooks();
    await tester.pumpWidget(
      withStubAssets(
        MaterialApp(
          home: ClassScreen(
            formatOverride: format,
            classData: _sample,
            captureController: hooks.controller,
            imageKey: hooks.imageKey,
            reserveKey: hooks.reserveKey,
          ),
        ),
      ),
    );
    return hooks;
  }

  /// Counted through the WHOLE tree, not just what is painted: a
  /// section a layout parks behind a tab still has to be there, and a
  /// duplicate parked there still has to fail.
  void expectExactlyOne(Type type) {
    expect(
      find.byType(type, skipOffstage: false),
      findsOneWidget,
      reason: 'exactly one $type must survive every arrangement',
    );
  }

  group('every class format carries every element of the screen', () {
    for (final format in ClassFormat.values) {
      testWidgets('$format', (tester) async {
        await pump(tester, format);

        // The chrome, with the only way off the screen that does not
        // commit to a booking.
        expectExactlyOne(AppTopbar);
        expectExactlyOne(TopbarBackButton);

        // The photo is never dropped — `specBrief` shrinks it to a
        // thumb, which is still one banner.
        expectExactlyOne(ClassImageBanner);

        // The four content sections.
        expectExactlyOne(ClassMetaSection);
        expectExactlyOne(ClassDetailsSection);
        expectExactlyOne(ClassInstructorSection);
        expectExactlyOne(ClassLocationSection);

        // The data the screen was handed actually reaches the meta,
        // and reaches the part of it that is on screen.
        expect(find.text(_sample.name), findsOneWidget);
      });
    }
  });

  group('every class format has exactly ONE reserve action', () {
    for (final format in ClassFormat.values) {
      testWidgets('$format', (tester) async {
        await pump(tester, format);

        expectExactlyOne(ClassReserveFooter);

        // Counted at the button, not just at the footer: a layout that
        // repeats the CTA outside the footer is caught here.
        expectExactlyOne(AppPrimaryButton);

        // And the one commit point is on screen, never parked behind a
        // tab or a scroll of an offstage pane.
        expect(find.text('Reserve your spot'), findsOneWidget);
      });
    }
  });

  group('every class format keeps the capture hooks', () {
    for (final format in ClassFormat.values) {
      testWidgets('$format', (tester) async {
        final hooks = await pump(tester, format);

        // The body scroll the harness drives is attached.
        expect(hooks.controller.hasClients, isTrue);

        // The image key still wraps the class photo, and the reserve
        // key still wraps the CTA, wherever the arrangement puts them.
        expect(
          find.descendant(
            of: find.byKey(hooks.imageKey, skipOffstage: false),
            matching: find.byType(ClassImageBanner, skipOffstage: false),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(hooks.reserveKey, skipOffstage: false),
            matching: find.byType(AppPrimaryButton, skipOffstage: false),
          ),
          findsOneWidget,
        );
      });
    }
  });

  group('every class format keeps the swipe into the post-class flow', () {
    for (final format in ClassFormat.values) {
      testWidgets('$format', (tester) async {
        await pump(tester, format);

        final swipes = tester
            .widgetList<GestureDetector>(
              find.byType(GestureDetector, skipOffstage: false),
            )
            .where((g) => g.onHorizontalDragEnd != null)
            .length;

        // The screen owns one; `sectionTabs` adds the tab swipe inside
        // its pane, which is that arrangement's own affordance.
        expect(swipes, format == ClassFormat.sectionTabs ? 2 : 1);
      });
    }
  });

  group('sectionTabs puts every section on screen through its tabs', () {
    /// The one arrangement that hides content behind a tap has to prove
    /// the tap reaches it: the sections it parks offstage are reachable,
    /// not orphaned.
    const owners = <String, Type>{
      'Details': ClassDetailsSection,
      'Instructor': ClassInstructorSection,
      'Location': ClassLocationSection,
    };

    for (final label in _kTabLabels) {
      testWidgets('the $label tab shows ${owners[label]}', (tester) async {
        await pump(tester, ClassFormat.sectionTabs);

        await tester.tap(
          find.descendant(
            of: find.byType(ClassTabBar),
            matching: find.text(label),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(owners[label]!), findsOneWidget);
      });
    }
  });
}
