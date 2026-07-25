import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/models/personal_info.dart';
import 'package:crm/features/member_details/data/models/retention.dart';
import 'package:crm/features/member_details/presentation/dialogs/freeze/freeze_account_dialog.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/shared/widgets/warning_message.dart';

class _MockMemberDetailBloc
    extends MockBloc<MemberDetailEvent, MemberDetailState>
    implements MemberDetailBloc {}

void main() {
  MembershipInfo membership(MembershipStatus status) => MembershipInfo(
        planId: 'plan-1',
        planName: 'Unlimited',
        planType: 'recurring',
        status: status,
        itemId: 'it_1',
        paidByMemberId: 'member-1',
        baseCost: 5000,
        durationAmount: 1,
        durationUnit: 'month',
        totalPrice: 5000,
        startDate: DateTime(2026, 1, 1),
      );

  MemberDetailResponse member(List<MembershipInfo> memberships) =>
      MemberDetailResponse(
        memberId: 'member-1',
        gymId: 'gym-1',
        firstName: 'Kid',
        lastName: 'Smith',
        membershipOverview: '1 membership',
        totalMonthlyRecurringPrice: 5000,
        totalMembershipCount: memberships.length,
        personalInfo: const PersonalInfo(),
        memberships: memberships,
        retention: const Retention(
          classStreakWeeks: 0,
          pointsBalance: 0,
          videosWatched: 0,
        ),
      );

  late _MockMemberDetailBloc bloc;

  setUp(() {
    bloc = _MockMemberDetailBloc();
    whenListen(
      bloc,
      const Stream<MemberDetailState>.empty(),
      initialState: const MemberDetailLoading(),
    );
  });

  Future<void> pump(
    WidgetTester tester,
    MemberDetailResponse detail,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<MemberDetailBloc>.value(
          value: bloc,
          child: FreezeAccountDialog(member: detail),
        ),
      ),
    );
  }

  testWidgets(
    'warns about the unpaid balance when a membership is overdue',
    (tester) async {
      await pump(tester, member([membership(MembershipStatus.overdue)]));

      expect(find.byType(WarningMessage), findsOneWidget);
      expect(find.text('Payment overdue'), findsOneWidget);
      // A warning, never a block — freeze stays available.
      expect(find.text('Freeze member'), findsWidgets);
    },
  );

  testWidgets('no warning when nothing is overdue', (tester) async {
    await pump(tester, member([membership(MembershipStatus.active)]));

    expect(find.byType(WarningMessage), findsNothing);
    expect(find.text('Payment overdue'), findsNothing);
  });
}
