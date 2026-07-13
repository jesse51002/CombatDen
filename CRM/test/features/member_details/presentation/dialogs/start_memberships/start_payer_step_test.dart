import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/member_details/data/models/linked_account.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/personal_info.dart';
import 'package:crm/features/member_details/data/models/retention.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_payer_step.dart';
import 'package:crm/shared/widgets/dashed_add_tile.dart';
import 'package:crm/shared/widgets/muted_add_tile.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  const launch = MemberDetailResponse(
    memberId: 'launch',
    gymId: 'gym-1',
    firstName: 'Lee',
    lastName: 'Launch',
    membershipOverview: 'No memberships',
    totalMonthlyRecurringPrice: 0,
    totalMembershipCount: 0,
    personalInfo: PersonalInfo(),
    retention: Retention(
      classStreakWeeks: 0,
      pointsBalance: 0,
      videosWatched: 0,
    ),
  );

  const payerCandidate = LinkedAccount(
    memberId: 'payer-1',
    firstName: 'Nia',
    lastName: 'Payer',
  );

  StartPayerStep build({
    VoidCallback? onNewPayer,
    VoidCallback? onLinkPayer,
  }) =>
      StartPayerStep(
        member: launch,
        candidates: const [payerCandidate],
        payerMemberId: 'launch',
        payerName: 'Lee Launch',
        selectedMemberId: 'launch',
        onSelected: (_) {},
        onNewPayer: onNewPayer ?? () {},
        onLinkPayer: onLinkPayer ?? () {},
      );

  testWidgets('lists the launch member (self-pay) and each authorized payer',
      (t) async {
    await t.pumpWidget(wrap(build()));

    expect(find.text('Who is paying?'), findsOneWidget);
    expect(find.text('Lee Launch'), findsOneWidget);
    expect(find.text('Nia Payer'), findsOneWidget);
  });

  testWidgets('offers the two adders below the candidates, in order',
      (t) async {
    await t.pumpWidget(wrap(build()));

    // Accent "New member" adder + muted "Link someone" adder, launch member's
    // first name woven into both subtitles.
    expect(find.byType(DashedAddTile), findsOneWidget);
    expect(find.byType(MutedAddTile), findsOneWidget);
    expect(find.text('New member'), findsOneWidget);
    expect(find.text('Link someone'), findsOneWidget);
    expect(
      find.text('Create someone new who pays for Lee.'),
      findsOneWidget,
    );
    expect(
      find.text('Choose an existing member to pay for Lee.'),
      findsOneWidget,
    );
  });

  testWidgets('tapping "New member" fires onNewPayer', (t) async {
    var tapped = false;
    await t.pumpWidget(wrap(build(onNewPayer: () => tapped = true)));

    await t.tap(find.text('New member'));
    expect(tapped, isTrue);
  });

  testWidgets('tapping "Link someone" fires onLinkPayer', (t) async {
    var tapped = false;
    await t.pumpWidget(wrap(build(onLinkPayer: () => tapped = true)));

    await t.tap(find.text('Link someone'));
    expect(tapped, isTrue);
  });
}
