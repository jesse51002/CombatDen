import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/kiosk/bloc/kiosk_session_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_det_chip.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_match_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_people_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_roster_row.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_signup_optional_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_training_toggle.dart';
import 'package:crm/features/member_details/data/models/duplicate_member_match.dart';
import 'package:crm/features/member_details/data/models/members_management_create_request.dart';
import 'package:crm/features/member_details/data/models/members_management_response.dart';
import 'package:crm/features/member_details/data/models/members_management_update_request.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/members_list/data/repositories/members_list_repository.dart';
import 'package:crm/features/memberships/data/repositories/memberships_repository.dart';

class _MockMemberRepository extends Mock implements MemberRepository {}

class _MockMembershipsRepository extends Mock
    implements MembershipsRepository {}

class _MockMembersListRepository extends Mock
    implements MembersListRepository {}

class _MockKioskSessionCubit extends Mock implements KioskSessionCubit {}

class _MockManagementResponse extends Mock
    implements MembersManagementResponse {}

/// The three GROUP screens render at iPad-landscape size with no layout
/// exception.
///
/// They are the fragile ones: the roster row packs an avatar, a name pair, a
/// chip, an intrinsic-width toggle, a pill and a remove button onto one line,
/// and the match step swaps its whole body between a confirm card and a live
/// search. A layout throw on an unattended lobby iPad is a red screen a member
/// is standing in front of, so this is the guard that they compose at all.
void main() {
  late KioskSignupCubit cubit;
  late _MockMemberRepository member;

  setUpAll(() {
    registerFallbackValue(
      const MembersManagementCreateRequest(
        gymId: 'gym-1',
        firstName: 'a',
        lastName: 'b',
      ),
    );
    registerFallbackValue(const MembersManagementUpdateRequest());
  });

  setUp(() {
    selectedGym.setActiveGym(
      gymId: 'gym-1',
      displayName: 'Iron Den',
      role: EmployeeRole.owner,
      timezone: 'America/Chicago',
      logoUrl: null,
    );
    final memberships = _MockMembershipsRepository();
    when(() => memberships.listPlans(any()))
        .thenAnswer((_) async => const <MembershipPlanResponse>[]);
    member = _MockMemberRepository();
    var seq = 0;
    when(() => member.createMember(any()))
        .thenAnswer((_) async => 'mem-${++seq}');
    when(() => member.updateMember(any(), any()))
        .thenAnswer((_) async => _MockManagementResponse());
    cubit = KioskSignupCubit(
      memberRepository: member,
      membershipsRepository: memberships,
      membersListRepository: _MockMembersListRepository(),
      session: _MockKioskSessionCubit(),
      gymId: 'gym-1',
    );
  });

  // The cubit owns a 5-minute idle Timer from its constructor, and the test
  // binding asserts no timer outlives the tree — so every test closes it
  // inside the body, before that invariant runs.

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.binding.setSurfaceSize(const Size(1180, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<KioskSignupCubit>.value(
            value: cubit,
            child: child,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The payer, created, standing on the roster with some details on file.
  Future<void> createPayer() async {
    cubit.submitDetails(
      firstName: 'Marcus',
      lastName: 'Bell',
      email: 'marcus.bell@gmail.com',
    );
    await cubit.submitExtraDetails(address: '4 Anvil Row');
  }

  testWidgets('the roster renders both rows, the toggle and one remove',
      (tester) async {
    await createPayer();
    await cubit.addPerson(
      firstName: 'Ella',
      lastName: 'Bell',
      email: 'ella.bell@gmail.com',
    );
    cubit.skipPersonDetails();
    await pump(tester, const KioskPeopleStep());

    expect(find.byType(KioskRosterRow), findsNWidgets(2));
    // The payer alone carries the "Training too" switch and the Paying pill.
    expect(find.byType(KioskTrainingToggle), findsOneWidget);
    expect(find.text('Paying'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    expect(find.byType(KioskDetChip), findsNWidgets(2));
    // The payer filled something in; the payee skipped. Neither is a problem.
    expect(find.text('Details added'), findsOneWidget);
    expect(find.text('None yet'), findsOneWidget);
    expect(find.text('Continue with 2 people'), findsOneWidget);
    await cubit.close();
  });

  testWidgets('a solo roster reads "It\'s just me"', (tester) async {
    await createPayer();
    await pump(tester, const KioskPeopleStep());

    expect(find.text('It\'s just me'), findsOneWidget);
    expect(find.byType(KioskRosterRow), findsOneWidget);
    expect(find.text('Add someone new'), findsOneWidget);
    await cubit.close();
  });

  testWidgets('the match step renders the confirm card with a MASKED email',
      (tester) async {
    await createPayer();
    when(() => member.createMember(any())).thenThrow(
      const DuplicateMemberException([
        DuplicateMemberMatch(
          memberId: 'mem-ella',
          firstName: 'Ella',
          lastName: 'Bell',
          email: 'ella.bell@gmail.com',
        ),
      ]),
    );
    await cubit.addPerson(
      firstName: 'Ella',
      lastName: 'Bell',
      email: 'ella.bell@gmail.com',
    );
    await pump(tester, const KioskMatchStep());

    expect(find.text('Is this the same Ella?'), findsOneWidget);
    expect(find.text('Yes, that\'s them'), findsOneWidget);
    expect(find.text('No — different person'), findsOneWidget);
    // The address is never printed in full on a shared screen.
    expect(find.textContaining('ella.bell@'), findsNothing);
    expect(find.text('e•••••@gmail.com'), findsNWidgets(2));
    await cubit.close();
  });

  testWidgets('a matched existing member gets a BLANK details form',
      (tester) async {
    await createPayer();
    when(() => member.createMember(any())).thenThrow(
      const DuplicateMemberException([
        DuplicateMemberMatch(
          memberId: 'mem-ella',
          firstName: 'Ella',
          lastName: 'Bell',
          email: 'ella.bell@gmail.com',
        ),
      ]),
    );
    await cubit.addPerson(
      firstName: 'Ella',
      lastName: 'Bell',
      email: 'ella.bell@gmail.com',
    );
    cubit.confirmMatch();
    await pump(tester, const KioskSignupOptionalStep());

    expect(find.text('A bit more about Ella'), findsOneWidget);
    expect(
      find.text(
        'Ella already has details with us — we don\'t show them on a shared '
        'screen.',
      ),
      findsOneWidget,
    );
    expect(find.text('Add Ella'), findsOneWidget);
    // The payer's own values never bleed into someone else's form either.
    expect(find.text('4 Anvil Row'), findsNothing);
    await cubit.close();
  });
}
