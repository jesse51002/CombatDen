import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_app/shared/widgets/topbar/app_topbar.dart';
import 'package:mobile_app/shared/widgets/topbar/topbar_header_section.dart';
import 'package:mobile_app/shared/widgets/topbar/topbar_identity_avatar.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: child),
    );

Widget _header({
  AppTopbarMode mode = AppTopbarMode.nameOnly,
  String? memberName,
  VoidCallback? onTap,
}) =>
    TopbarHeaderSection(
      mode: mode,
      showBackButton: false,
      gymName: 'Iron Fist MMA',
      logoAsset: 'gym_logo_global_mma.png',
      memberName: memberName,
      memberFirstName: 'Jesse',
      memberLastName: 'Musa',
      onTitleTap: onTap ?? () {},
    );

void main() {
  group('TopbarHeaderSection identity control', () {
    testWidgets('renders the avatar in the trailing flank (nameOnly)',
        (tester) async {
      await tester.pumpWidget(_host(_header(memberName: 'Jesse Musa')));

      expect(find.text('Iron Fist MMA'), findsOneWidget);
      expect(find.byType(TopbarIdentityAvatar), findsOneWidget);

      final section = tester.getCenter(find.byType(TopbarHeaderSection));
      final avatar = tester.getCenter(find.byType(TopbarIdentityAvatar));
      expect(avatar.dx, greaterThan(section.dx));
    });

    testWidgets('renders the avatar in the trailing flank (bigLogo)',
        (tester) async {
      await tester.pumpWidget(
        _host(_header(mode: AppTopbarMode.bigLogo, memberName: 'Jesse Musa')),
      );

      expect(find.byType(TopbarIdentityAvatar), findsOneWidget);

      final section = tester.getRect(find.byType(TopbarHeaderSection));
      final avatar = tester.getRect(find.byType(TopbarIdentityAvatar));
      expect(avatar.center.dx, greaterThan(section.center.dx));
      // Rides the TOP edge rather than floating against the 100pt logo.
      expect(avatar.center.dy, lessThan(section.center.dy));
    });

    testWidgets('renders the avatar even with no member name', (tester) async {
      await tester.pumpWidget(_host(_header()));

      expect(find.text('Iron Fist MMA'), findsOneWidget);
      expect(find.byType(TopbarIdentityAvatar), findsOneWidget);
    });

    testWidgets('the member name is never rendered inside the title',
        (tester) async {
      await tester.pumpWidget(_host(_header(memberName: 'Jesse Musa')));

      expect(find.text('Jesse Musa'), findsNothing);
    });

    testWidgets('the gym title stays a tap target', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(_header(memberName: 'Jesse Musa', onTap: () => taps++)),
      );

      await tester.tap(find.text('Iron Fist MMA'));
      expect(taps, 1);
    });

    testWidgets('a long gym name never runs under the trailing avatar',
        (tester) async {
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 360,
            child: TopbarHeaderSection(
              mode: AppTopbarMode.nameOnly,
              showBackButton: true,
              gymName: 'Iron Fist Mixed Martial Arts and Boxing Academy of '
                  'Greater Springfield',
              logoAsset: 'gym_logo_global_mma.png',
              memberName: 'Jesse Musa',
              onTitleTap: () {},
            ),
          ),
        ),
      );

      final title = tester.getRect(find.byType(Text).first);
      final avatar = tester.getRect(find.byType(TopbarIdentityAvatar));
      expect(title.right, lessThanOrEqualTo(avatar.left));
    });

    testWidgets('ellipsizes a long gym name on a single line', (tester) async {
      await tester.pumpWidget(
        _host(_header(memberName: 'Jesse Musa')),
      );

      final gym = tester.widget<Text>(find.text('Iron Fist MMA'));
      expect(gym.maxLines, 1);
      expect(gym.overflow, TextOverflow.ellipsis);
    });
  });
}
