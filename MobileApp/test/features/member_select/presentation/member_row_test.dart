import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_app/features/member_select/data/models/member_identity.dart';
import 'package:mobile_app/features/member_select/presentation/widgets/member_row.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: child),
    );

MemberIdentity _member({String? gymLogoUrl}) => MemberIdentity(
      memberId: 'm1',
      gymId: 'g1',
      gymName: 'Iron Fist MMA',
      firstName: 'Jesse',
      lastName: 'Musa',
      gymLogoUrl: gymLogoUrl,
    );

void main() {
  group('MemberRow', () {
    testWidgets('renders the member name over the gym name', (tester) async {
      await tester.pumpWidget(
        _host(MemberRow(member: _member(), onTap: () {})),
      );

      expect(find.text('Jesse Musa'), findsOneWidget);
      expect(find.text('Iron Fist MMA'), findsOneWidget);
    });

    testWidgets('renders the gym logo tile when the gym has a logo',
        (tester) async {
      await tester.pumpWidget(
        _host(
          MemberRow(
            member: _member(gymLogoUrl: 'https://cdn.test/logo.png'),
            onTap: () {},
          ),
        ),
      );

      expect(find.byType(CachedNetworkImage), findsOneWidget);
      expect(find.text('Iron Fist MMA'), findsOneWidget);
    });

    testWidgets('omits the logo tile entirely when logo_url is null',
        (tester) async {
      await tester.pumpWidget(
        _host(MemberRow(member: _member(), onTap: () {})),
      );

      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.text('Iron Fist MMA'), findsOneWidget);
    });

    testWidgets('omits the logo tile when logo_url is empty', (tester) async {
      await tester.pumpWidget(
        _host(MemberRow(member: _member(gymLogoUrl: ''), onTap: () {})),
      );

      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets('taps through', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(MemberRow(member: _member(), onTap: () => taps++)),
      );

      await tester.tap(find.text('Jesse Musa'));
      expect(taps, 1);
    });
  });
}
