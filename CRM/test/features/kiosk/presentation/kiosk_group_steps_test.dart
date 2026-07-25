import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/kiosk/bloc/kiosk_session_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_consent_check.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_match_search.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_match_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_name_row.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_payer_pick_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_people_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_roster_row.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_signup_optional_step.dart';
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
/// exception. They are the fragile ones — the roster row packs an avatar, a
/// name pair, a chip, an intrinsic-width toggle, a pill and a remove button
/// onto one line — and a layout throw on an unattended lobby iPad is a red
/// screen a member is standing in front of.
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

  // The cubit owns a 5-minute idle Timer, and the binding asserts no timer
  // outlives the tree — so every test closes it inside the body.

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
    // The membership check is on EVERY row, not just the payer's.
    expect(find.byType(KioskConsentCheck), findsNWidgets(2));
    expect(find.text('Paying'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    // Both were created here, so both may be corrected.
    expect(find.text('Edit'), findsNWidgets(2));
    expect(find.text('Continue with 2 people'), findsOneWidget);
    await cubit.close();
  });

  testWidgets('an EXISTING member gets no Edit — the kiosk owns no record '
      'of theirs', (tester) async {
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
    await pump(tester, const KioskPeopleStep());

    expect(find.byType(KioskRosterRow), findsNWidgets(2));
    expect(find.text('Member'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    await cubit.close();
  });

  testWidgets('the roster prints every address MASKED, the gym\'s own record '
      'included', (tester) async {
    await createPayer();
    // Ella's row carries the address the GYM holds, deliberately different
    // from what was typed, so this asserts her record, not an echo of input.
    when(() => member.createMember(any())).thenThrow(
      const DuplicateMemberException([
        DuplicateMemberMatch(
          memberId: 'mem-ella',
          firstName: 'Ella',
          lastName: 'Bell',
          email: 'ella.bell@icloud.com',
        ),
      ]),
    );
    await cubit.addPerson(
      firstName: 'Ella',
      lastName: 'Bell',
      email: 'ella.typed@gmail.com',
    );
    cubit.confirmMatch();
    await pump(tester, const KioskPeopleStep());

    // Privacy on the one screen that lists EVERYBODY at once: a lobby queue
    // reads it over the member's shoulder, so no address is printed in full.
    expect(find.byType(KioskRosterRow), findsNWidgets(2));
    expect(find.text('m•••••@gmail.com'), findsOneWidget);
    expect(find.text('e•••••@icloud.com'), findsOneWidget);
    expect(find.textContaining('marcus.bell@'), findsNothing);
    expect(find.textContaining('ella.bell@'), findsNothing);
    expect(find.textContaining('ella.typed@'), findsNothing);
    expect(tester.takeException(), isNull);
    await cubit.close();
  });

  testWidgets('the roster offers to hand the paying over', (tester) async {
    await createPayer();
    await pump(tester, const KioskPeopleStep());

    expect(find.text('Change who is paying'), findsOneWidget);
    await cubit.close();
  });

  testWidgets('the membership check is per person, stacked, and ON by default',
      (tester) async {
    await createPayer();
    await cubit.addPerson(
      firstName: 'Ella',
      lastName: 'Bell',
      email: 'ella.bell@gmail.com',
    );
    cubit.skipPersonDetails();
    await pump(tester, const KioskPeopleStep());

    expect(find.byType(KioskConsentCheck), findsNWidgets(2));
    expect(
      find.text('Marcus is getting a membership as well'),
      findsOneWidget,
    );
    expect(find.text('Ella is getting a membership as well'), findsOneWidget);
    expect(cubit.state.persons.every((p) => p.training), isTrue);
    // The check sits on its OWN line under the identity row, not inline.
    final row = tester.getRect(find.byType(KioskRosterRow).first);
    final check = tester.getRect(find.byType(KioskConsentCheck).first);
    expect(check.top, greaterThan(row.top));
    expect(tester.takeException(), isNull);
    await cubit.close();
  });

  testWidgets('a solo roster drops the "as well"', (tester) async {
    await createPayer();
    await pump(tester, const KioskPeopleStep());

    expect(find.text('I\'m getting a membership'), findsOneWidget);
    expect(find.textContaining('as well'), findsNothing);
    await cubit.close();
  });

  testWidgets('unticking everyone blocks Continue and SAYS why',
      (tester) async {
    await createPayer();
    cubit.setPersonTraining(0, false);
    await pump(tester, const KioskPeopleStep());

    // A disabled button is never left to explain itself.
    expect(
      find.textContaining('we need at least one to carry on'),
      findsOneWidget,
    );
    final primary = tester.widget<KioskPrimaryButton>(
      find.widgetWithText(KioskPrimaryButton, 'It\'s just me'),
    );
    expect(primary.onPressed, isNull);

    // Ticking anybody releases it.
    cubit.setPersonTraining(0, true);
    // The emit lands on a microtask, so the NEXT frame carries the change.
    await tester.pump();
    await tester.pump();
    expect(
      find.textContaining('we need at least one to carry on'),
      findsNothing,
    );
    expect(
      tester
          .widget<KioskPrimaryButton>(
            find.widgetWithText(KioskPrimaryButton, 'It\'s just me'),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
    await cubit.close();
  });

  testWidgets('the picker lists the roster AND the CRM search together',
      (tester) async {
    await createPayer();
    await cubit.addPerson(
      firstName: 'Ella',
      lastName: 'Bell',
      email: 'ella.bell@gmail.com',
    );
    cubit.skipPersonDetails();
    cubit.openPayerPick();
    await pump(tester, const KioskPayerPickStep());

    expect(find.text('Already here'), findsOneWidget);
    expect(find.text('Someone else who trains here'), findsOneWidget);
    // Ella is offered; the current payer is named as context, not as a row.
    expect(find.byType(KioskNameRow), findsOneWidget);
    expect(find.text('Ella Bell'), findsOneWidget);
    expect(find.text('PAYING NOW'), findsOneWidget);
    expect(find.byType(KioskMatchSearch), findsOneWidget);
    // A shared iPad never prints an address in full.
    expect(find.textContaining('ella.bell@'), findsNothing);
    expect(tester.takeException(), isNull);
    await cubit.close();
  });

  testWidgets('the remove control asks before it removes', (tester) async {
    await createPayer();
    await cubit.addPerson(
      firstName: 'Ella',
      lastName: 'Bell',
      email: 'ella.bell@gmail.com',
    );
    cubit.skipPersonDetails();
    await pump(tester, const KioskPeopleStep());

    await tester.tap(find.bySemanticsLabel('Remove Ella Bell'));
    await tester.pump();
    expect(cubit.state.removeConfirmIndex, 1);
    // Nothing has happened yet.
    expect(cubit.state.persons, hasLength(2));
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

  testWidgets('a NEW payee\'s details form opens empty of the payer\'s values',
      (tester) async {
    await createPayer();
    await cubit.addPerson(
      firstName: 'Ella',
      lastName: 'Bell',
      email: 'ella.bell@gmail.com',
    );
    await pump(tester, const KioskSignupOptionalStep());

    expect(find.text('A bit more about Ella'), findsOneWidget);
    expect(find.text('Add Ella'), findsOneWidget);
    // The payer's own values never bleed into someone else's form.
    expect(find.text('4 Anvil Row'), findsNothing);
    await cubit.close();
  });
}
