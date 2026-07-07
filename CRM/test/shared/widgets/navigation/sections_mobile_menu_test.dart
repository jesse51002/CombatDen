import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/shared/widgets/navigation/nav_sections.dart';
import 'package:crm/shared/widgets/navigation/sections_mobile_menu.dart';

void main() {
  // Reproduces production: the menu is shown via the app Overlay, which has no
  // Material ancestor. If the menu didn't provide its own Material, the rows'
  // InkWells would throw "No Material widget found" on build — this guards that.
  testWidgets(
    'renders and taps rows inside a bare Overlay (no Material ancestor)',
    (tester) async {
      NavSection? selected;
      var loggedOut = false;

      await tester.pumpWidget(
        MaterialApp(
          // Disable the M3 ink splash: its `ink_sparkle` shader fails to decode
          // in this test SDK (version skew), unrelated to what we're testing.
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          // MaterialApp does NOT wrap `home` in a Material, so an Overlay here
          // mirrors the real chrome: no Material above the menu.
          home: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (_) => SectionsMobileMenu(
                  activeRoute: AppRoutes.members,
                  onSelect: (section) => selected = section,
                  onLogout: () => loggedOut = true,
                ),
              ),
            ],
          ),
        ),
      );

      // Built without throwing, and the rows + Logout are present.
      expect(tester.takeException(), isNull);
      // The Members + Employees sections are now one combined "People" entry.
      expect(find.text('People'), findsOneWidget);
      // The Memberships section is now labelled "Gym" (route unchanged).
      expect(find.text('Gym'), findsOneWidget);
      expect(find.text('Logout'), findsOneWidget);

      // A section row fires onSelect with that section.
      await tester.tap(find.text('Gym'));
      expect(selected?.route, AppRoutes.memberships);

      // The Logout row fires onLogout.
      await tester.tap(find.text('Logout'));
      expect(loggedOut, isTrue);
    },
  );
}
