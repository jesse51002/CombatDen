import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_session_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_return_timer.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_section_head.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_card_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_declined_screen.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_entry_choice_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_identify_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_name_row.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_payer_pick_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_people_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_plan_pick_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_results_screen.dart';
import 'package:crm/features/member_details/data/models/authorized_payer_waiver.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_preview.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_response.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_result_item.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_status.dart';
import 'package:crm/features/member_details/data/models/members_management_create_request.dart';
import 'package:crm/features/member_details/data/models/members_management_response.dart';
import 'package:crm/features/member_details/data/models/members_management_update_request.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/models/membership_plan_price_response.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';
import 'package:crm/features/member_details/data/models/personal_info.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/member_details/data/models/retention.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/member_details/presentation/dialogs/card_field_box.dart';
import 'package:crm/features/members_list/data/models/crm_members_list_request.dart';
import 'package:crm/features/members_list/data/models/crm_members_list_response.dart';
import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/features/members_list/data/models/members_list_filters.dart';
import 'package:crm/features/members_list/data/models/members_list_view.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/features/members_list/data/repositories/members_list_repository.dart';
import 'package:crm/features/membership_flow/config/membership_flow_scale.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_buttons.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_card_chip.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_plan_block.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_plan_card.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_plan_picked_banner.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_result_row.dart';
import 'package:crm/features/memberships/data/models/waiver_response.dart';
import 'package:crm/features/memberships/data/models/waiver_signature_response.dart';
import 'package:crm/features/memberships/data/models/waiver_type.dart';
import 'package:crm/features/memberships/data/models/waiver_version_response.dart';
import 'package:crm/features/memberships/data/repositories/memberships_repository.dart';
import 'package:crm/shared/widgets/class_row/instructor_avatar.dart';

class _MockMemberRepository extends Mock implements MemberRepository {}

class _MockMembershipsRepository extends Mock
    implements MembershipsRepository {}

class _MockMembersListRepository extends Mock
    implements MembersListRepository {}

class _MockKioskSessionCubit extends Mock implements KioskSessionCubit {}

class _MockManagementResponse extends Mock
    implements MembersManagementResponse {}

class _MockSignatureResponse extends Mock implements WaiverSignatureResponse {}

/// The signup surfaces, rendered at both real folds (1180x820 and 1024x700).
/// A layout throw on an unattended lobby iPad is a red screen a member is
/// standing in front of, so composition is asserted, never assumed.
void main() {
  late KioskSignupCubit cubit;
  late _MockMemberRepository member;
  late _MockMembershipsRepository memberships;
  late _MockMembersListRepository membersList;
  late int createSeq;

  setUpAll(() {
    registerFallbackValue(
      const MembersManagementCreateRequest(
        gymId: 'gym-1',
        firstName: 'a',
        lastName: 'b',
      ),
    );
    registerFallbackValue(const MembersManagementUpdateRequest());
    registerFallbackValue(
      const MemberMembershipsStartRequest(
        payerMemberId: 'm',
        gymId: 'gym-1',
        idempotencyKey: 'k',
        memberships: [],
      ),
    );
    registerFallbackValue(
      const CrmMembersListRequest(
        gymId: 'gym-1',
        view: MembersListView.all,
        filters: MembersListFilters(),
        startIndex: 0,
        count: 8,
      ),
    );
  });

  setUp(() {
    selectedGym.setActiveGym(
      gymId: 'gym-1',
      displayName: 'Iron Den',
      role: EmployeeRole.owner,
      timezone: 'America/Chicago',
      logoUrl: null,
      // A connected account so CardFieldBox mounts the live card field
      // (payments available); the suite no-ops the real Stripe apply.
      stripeAccountId: 'acct_iron',
    );
    createSeq = 0;
    memberships = _MockMembershipsRepository();
    membersList = _MockMembersListRepository();
    when(() => memberships.listPlans(any()))
        .thenAnswer((_) async => [_plan()]);
    when(() => memberships.getWaiver(any(), any()))
        .thenAnswer((_) async => _waiver());
    when(
      () => memberships.recordWaiverSignature(
        waiverId: any(named: 'waiverId'),
        gymId: any(named: 'gymId'),
        memberId: any(named: 'memberId'),
        waiverVersionId: any(named: 'waiverVersionId'),
        signerName: any(named: 'signerName'),
      ),
    ).thenAnswer((_) async => _MockSignatureResponse());
    member = _MockMemberRepository();
    when(() => member.createMember(any()))
        .thenAnswer((_) async => 'mem-${++createSeq}');
    when(() => member.updateMember(any(), any()))
        .thenAnswer((_) async => _MockManagementResponse());
    when(() => member.getAuthorizedPayerWaiver(any())).thenAnswer(
      (_) async => const AuthorizedPayerWaiver(
        waiverId: 'payer-waiver-1',
        versionId: 'payer-ver-1',
        name: 'Authorized Payer Agreement',
        body: 'I authorise myself to pay for {{payee_name}}.',
      ),
    );
    when(
      () => member.linkMemberAccount(
        any(),
        payerMemberId: any(named: 'payerMemberId'),
        waiverVersionId: any(named: 'waiverVersionId'),
        signerName: any(named: 'signerName'),
        consentAcknowledged: any(named: 'consentAcknowledged'),
      ),
    ).thenAnswer((_) async {});
    when(() => member.previewStartMemberships(any()))
        .thenAnswer((_) async => _preview());
    when(
      () => member.startMemberships(
        any(),
        receiveTimeout: any(named: 'receiveTimeout'),
      ),
    ).thenAnswer((_) async => _startResponse());
    when(() => membersList.getMembersList(any()))
        .thenAnswer((_) async => _page(const []));
  });

  KioskSignupCubit newCubit() => KioskSignupCubit(
        memberRepository: member,
        membershipsRepository: memberships,
        membersListRepository: membersList,
        session: _MockKioskSessionCubit(),
        gymId: 'gym-1',
      );

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(1180, 820),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        // The kiosk SURFACE's scale, mounted the way `KioskSignupScreen`
        // does: the shared flow components carry no size of their own.
        builder: (context, child) => MembershipFlowTheme(
          scale: const MembershipFlowScale.kiosk(),
          child: child!,
        ),
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

  Future<void> createPayer() async {
    cubit.submitDetails(
      firstName: 'Marcus',
      lastName: 'Bell',
      email: 'marcus.bell@gmail.com',
    );
    await cubit.submitExtraDetails();
  }

  Future<void> addElla() async {
    await cubit.addPerson(
      firstName: 'Ella',
      lastName: 'Bell',
      email: 'ella.bell@gmail.com',
    );
    cubit.skipPersonDetails();
  }

  void deletePayer() {
    cubit.askRemovePerson(0);
    cubit.confirmRemovePerson();
  }

  /// Adopt an EXISTING member (so their history is read at all) and land on the
  /// plan grid with [detail] as that history and [plans] as the catalogue.
  Future<void> atPlansAsExisting(
    WidgetTester tester, {
    required MemberDetailResponse detail,
    required List<MembershipPlanResponse> plans,
  }) async {
    when(() => memberships.listPlans(any())).thenAnswer((_) async => plans);
    when(() => member.getMemberDetail(any())).thenAnswer((_) async => detail);
    cubit = newCubit();
    cubit.startAsExistingMember();
    await cubit.pickPayerRow(
      AllViewRow(
        memberId: 'mem-old',
        name: 'Marcus Bell',
        email: 'marcus.bell@gmail.com',
        membershipStatus: MembershipStatus.active,
        membershipText: 'Monthly',
      ),
    );
    cubit.confirmPayerMatch();
    cubit.continueToPlans();
    await tester.pump();
  }

  /// Walk a GROUP of [people] down the real spine to a start landing as
  /// [landed], so the results screen is reached as a member reaches it.
  Future<void> atGroupResults(
    WidgetTester tester, {
    required int people,
    required MemberMembershipsStartResponse landed,
  }) async {
    createSeq = 0;
    cubit = newCubit();
    await createPayer();
    for (var i = 1; i < people; i++) {
      await cubit.addPerson(
        firstName: 'Kid$i',
        lastName: 'Bell',
        email: 'kid$i.bell@gmail.com',
      );
      cubit.skipPersonDetails();
    }
    cubit.continueToPlans();
    await tester.pump();
    for (var i = 0; i < people; i++) {
      cubit.selectPlan('plan-1');
      cubit.continueFromPlans();
      await tester.pump();
    }
    // The waiver run is grouped by PERSON: each payee's payer-auth then their
    // own liability waiver, the payer's own last.
    var guard = 0;
    while (cubit.state.step == KioskSignupStep.waivers && guard++ < 40) {
      if (cubit.state.payerAuthPending) {
        await cubit.signPayerAuth(signerName: 'Marcus Bell');
      } else {
        await cubit.signWaiver(signerName: 'Marcus Bell');
      }
      await tester.pump();
    }
    expect(cubit.state.step, KioskSignupStep.card);
    cubit.submitCard(paymentMethodId: 'pm_1', brand: 'visa', last4: '4242');
    await tester.pump();
    when(
      () => member.startMemberships(
        any(),
        receiveTimeout: any(named: 'receiveTimeout'),
      ),
    ).thenAnswer((_) async => landed);
    await cubit.pay();
  }

  /// Walk a solo signup to the review, then decline the charge [times] times.
  /// Pumps rather than `Future.delayed`: under the fake clock a zero-duration
  /// timer never fires without a pump.
  Future<void> declineTimes(WidgetTester tester, int times) async {
    await createPayer();
    cubit.continueToPlans();
    cubit.selectPlan('plan-1');
    cubit.continueFromPlans();
    await tester.pump();
    await cubit.signWaiver(signerName: 'Marcus Bell');
    cubit.submitCard(paymentMethodId: 'pm_1', brand: 'visa', last4: '4242');
    await tester.pump();
    when(
      () => member.startMemberships(
        any(),
        receiveTimeout: any(named: 'receiveTimeout'),
      ),
    ).thenAnswer((_) async => _startResponse(failed: true));
    await cubit.pay();
    for (var i = 2; i <= times; i++) {
      cubit.retryCard();
      cubit.submitCard(paymentMethodId: 'pm_$i', brand: 'visa', last4: '4242');
      await tester.pump();
      await cubit.pay();
    }
  }

  group('· the front door offers both ways in', () {
    testWidgets('the entry fork renders both halves at either fold',
        (tester) async {
      for (final size in const [Size(1180, 820), Size(1024, 700)]) {
        cubit = newCubit();
        await pump(tester, const KioskEntryChoiceStep(), size: size);

        expect(find.text('New to the gym'), findsOneWidget);
        expect(find.text('Already a member'), findsOneWidget);
        // Different tiers on purpose: two gradient primaries break the button
        // ladder, two outlines leave the screen with no primary.
        expect(
          find.widgetWithText(KioskPrimaryButton, 'I\'m new here'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(KioskOutlineButton, 'Find my name'),
          findsOneWidget,
        );
        // Step 1: no Back, and the escape is the way out.
        expect(find.text('Back'), findsNothing);
        expect(find.text('Start over'), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: 'the entry fork overflowed at $size',
        );
        await cubit.close();
      }
    });

    testWidgets('the identify search offers avatar-free FULL-name rows only',
        (tester) async {
      when(() => membersList.getMembersList(any())).thenAnswer(
        (_) async => _page([
          AllViewRow(
            memberId: 'mem-old',
            name: 'Marcus Bell',
            email: 'marcus.bell@gmail.com',
            membershipStatus: MembershipStatus.active,
            membershipText: 'Monthly',
          ),
        ]),
      );
      cubit = newCubit();
      cubit.startAsExistingMember();
      cubit.searchExistingPeople('marcus');
      await tester.pump(kKioskSearchDebounce);
      await pump(tester, const KioskIdentifyStep());

      expect(find.text('Find your name'), findsOneWidget);
      final row = find.widgetWithText(KioskNameRow, 'Marcus Bell');
      expect(row, findsOneWidget);
      // A shared lobby iPad prints no face and no address here; the masked
      // email belongs to the confirm card, one step later.
      expect(
        find.descendant(of: row, matching: find.byType(InstructorAvatar)),
        findsNothing,
      );
      expect(find.textContaining('marcus.bell@gmail.com'), findsNothing);
      expect(tester.takeException(), isNull);
      await cubit.close();
    });
  });

  group('A · the payer picker reads as pickable', () {
    testWidgets('rows are contained tappable KioskNameRows over quiet heads',
        (tester) async {
      cubit = newCubit();
      await createPayer();
      await addElla();
      cubit.openPayerPick();
      await pump(tester, const KioskPayerPickStep());

      expect(find.byType(KioskNameRow), findsOneWidget);
      expect(find.byIcon(Symbols.chevron_right_sharp), findsWidgets);
      expect(find.text('Already here'), findsOneWidget);
      expect(find.text('Someone else who trains here'), findsOneWidget);
      final head = tester.widget<KioskSectionHead>(
        find.widgetWithText(KioskSectionHead, 'Already here'),
      );
      expect(head.quiet, isTrue);
      expect(tester.takeException(), isNull);
      await cubit.close();
    });
  });

  group('B · the payer is deletable, and its absence blocks legibly', () {
    testWidgets('the payer row carries a trash control', (tester) async {
      cubit = newCubit();
      await createPayer();
      await addElla();
      await pump(tester, const KioskPeopleStep());

      expect(find.bySemanticsLabel('Remove Marcus Bell'), findsOneWidget);
      expect(find.bySemanticsLabel('Remove Ella Bell'), findsOneWidget);
      await cubit.close();
    });

    testWidgets('deleting the payer blocks Continue with a reason and a way to '
        'choose', (tester) async {
      cubit = newCubit();
      await createPayer();
      await addElla();
      deletePayer();
      // Back out of the picker without choosing → the People step, no payer.
      cubit.back();
      await pump(tester, const KioskPeopleStep());

      expect(find.text('Choose who\'s paying to continue.'), findsOneWidget);
      expect(
        find.widgetWithText(KioskOutlineButton, 'Choose who\'s paying'),
        findsOneWidget,
      );
      final primary = tester.widget<FlowPrimaryButton>(
        find.byType(FlowPrimaryButton),
      );
      expect(primary.onPressed, isNull);
      expect(tester.takeException(), isNull);
      await cubit.close();
    });

    testWidgets('the picker drops the PAYING NOW strip when there is no payer',
        (tester) async {
      cubit = newCubit();
      await createPayer();
      await addElla();
      deletePayer();
      await pump(tester, const KioskPayerPickStep());

      expect(find.text('PAYING NOW'), findsNothing);
      expect(find.byType(KioskNameRow), findsOneWidget);
      expect(find.text('Ella Bell'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await cubit.close();
    });
  });

  group('C · the plan pick confirms the choice', () {
    testWidgets('picking a plan surfaces the confirmation banner naming it',
        (tester) async {
      cubit = newCubit();
      await createPayer();
      cubit.continueToPlans();
      await tester.pump();
      await pump(tester, const KioskPlanPickStep());

      expect(find.byType(FlowPlanPickedBanner), findsNothing);

      await tester.tap(find.byType(FlowPlanCard).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(FlowPlanPickedBanner), findsOneWidget);
      expect(find.text('YOU\'VE PICKED'), findsOneWidget);
      expect(find.text('Unlimited'), findsWidgets);
      expect(tester.takeException(), isNull);
      await cubit.close();
    });

    testWidgets('a trial the member has already had renders USED and explains '
        'instead of selecting', (tester) async {
      await atPlansAsExisting(
        tester,
        detail: _detailWithTrial(),
        plans: [_plan(), _trialPlan()],
      );
      await pump(tester, const KioskPlanPickStep());

      expect(find.text('Already used'), findsOneWidget);

      await tester.tap(find.widgetWithText(FlowPlanCard, 'Two-week trial'));
      await tester.pump();
      // The tap EXPLAINS and selects nothing: a blocked plan must never reach
      // the review and fail at pay.
      expect(cubit.state.activePerson.selectedPlanId, isNull);
      expect(
        cubit.state.planBlockActive,
        KioskPlanBlockReason.trialUsed,
      );
      expect(find.byType(FlowPlanPickedBanner), findsNothing);
      expect(tester.takeException(), isNull);
      await cubit.close();
    });

    testWidgets('the trial popup carries its countdown and both ways out at '
        'either fold', (tester) async {
      for (final size in const [Size(1180, 820), Size(1024, 700)]) {
        await atPlansAsExisting(
          tester,
          detail: _detailWithTrial(),
          plans: [_plan(), _trialPlan()],
        );
        cubit.selectPlan('plan-trial');
        await pump(tester, const FlowPlanBlock(), size: size);

        expect(find.text('You\'ve already had a trial'), findsOneWidget);
        expect(
          find.textContaining('Trials are one to a member'),
          findsOneWidget,
        );
        // Never names a PLAN: the rule is per member, so naming one would
        // describe a narrower rule than the grid enforces.
        expect(find.textContaining('Two-week trial'), findsNothing);
        expect(
          find.widgetWithText(FlowPrimaryButton, 'Pick a membership'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(FlowOutlineButton, 'Get help at the desk'),
          findsOneWidget,
        );
        // No blocking overlay may hold a shared iPad forever.
        expect(find.byType(KioskReturnTimer), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: 'the trial popup overflowed at $size',
        );
        await cubit.close();
      }
    });

    testWidgets('a membership the member already holds is marked "You have '
        'this", stated in a notice, and explains by NAME', (tester) async {
      await atPlansAsExisting(
        tester,
        detail: _detailHolding('plan-1', 'recurring'),
        plans: [_plan(), _secondRecurringPlan()],
      );
      await pump(tester, const KioskPlanPickStep());

      expect(find.text('You have this'), findsOneWidget);
      expect(find.text('Already used'), findsNothing);
      // Founder ruling: the current membership is NAMED above the grid, not
      // left behind a tap.
      expect(
        find.textContaining('You\'re on Unlimited right now'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(FlowPlanCard, 'Unlimited'));
      await tester.pump();
      expect(cubit.state.activePerson.selectedPlanId, isNull);
      expect(
        cubit.state.planBlockActive,
        KioskPlanBlockReason.alreadyOnPlan,
      );

      await pump(tester, const FlowPlanBlock());
      expect(find.text('You already have this membership'), findsOneWidget);
      // This popup DOES name the plan — the backend's rule is per plan, so
      // naming it describes the rule exactly.
      expect(find.textContaining('You\'re on Unlimited right now'), findsWidgets);
      // Lobby privacy: a plan NAME and nothing else — no price, no dates, no
      // status word.
      expect(find.textContaining('frozen'), findsNothing);
      expect(find.textContaining('Frozen'), findsNothing);
      expect(tester.takeException(), isNull);
      await cubit.close();
    });

    testWidgets('a DIFFERENT recurring plan stays fully selectable — the '
        'over-block guard', (tester) async {
      await atPlansAsExisting(
        tester,
        detail: _detailHolding('plan-1', 'recurring'),
        plans: [_plan(), _secondRecurringPlan()],
      );
      await pump(tester, const KioskPlanPickStep());

      // The rule is PER PLAN: a member on one recurring plan may still buy a
      // different one, and a false block turns a paying customer away.
      await tester.tap(find.widgetWithText(FlowPlanCard, 'Two classes a week'));
      await tester.pump();
      expect(cubit.state.activePerson.selectedPlanId, 'plan-2');
      expect(cubit.state.planBlockActive, isNull);
      expect(tester.takeException(), isNull);
      await cubit.close();
    });
  });

  group('D · the card field and the decline popup', () {
    testWidgets('the card field is re-keyed per attempt', (tester) async {
      cubit = newCubit();
      await pump(tester, const KioskCardStep());

      final key0 =
          tester.widget<CardFieldBox>(find.byType(CardFieldBox)).fieldKey;
      expect(key0, const ValueKey('kiosk-card-0'));

      // The emit lands on a microtask, so the NEXT frame carries the new key.
      cubit.retryCard();
      await tester.pump();
      await tester.pump();
      final key1 =
          tester.widget<CardFieldBox>(find.byType(CardFieldBox)).fieldKey;
      expect(key1, const ValueKey('kiosk-card-1'));
      expect(key0, isNot(key1));
      expect(tester.takeException(), isNull);
      await cubit.close();
    });

    testWidgets('the decline popup stacks Retry / Try another card / Get help '
        'over its countdown, with no overflow at the fold', (tester) async {
      cubit = newCubit();
      await declineTimes(tester, 1);
      await pump(tester, const KioskDeclinedScreen());

      expect(find.text('Your bank declined the payment'), findsOneWidget);
      // The countdown is a RETURN clock, not a cooldown: it never gates Retry,
      // and no "you can try again in" exists anywhere.
      expect(find.byType(KioskReturnTimer), findsOneWidget);
      expect(
        find.text('Back to start in ${kKioskSignupPopupHold.inSeconds}s'),
        findsOneWidget,
      );
      expect(find.textContaining('You can try again in'), findsNothing);

      // All three are live from the FIRST frame — no cooldown, no attempt cap.
      final retry = tester.widget<KioskPrimaryButton>(
        find.widgetWithText(KioskPrimaryButton, 'Retry'),
      );
      expect(retry.onPressed, isNotNull);
      final tryAnother = tester.widget<KioskOutlineButton>(
        find.widgetWithText(KioskOutlineButton, 'Try another card'),
      );
      expect(tryAnother.onPressed, isNotNull);
      final help = tester.widget<KioskOutlineButton>(
        find.widgetWithText(KioskOutlineButton, 'Get help at the desk'),
      );
      expect(help.onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      await cubit.close();
    });

    testWidgets('the decline body does not claim the ACCOUNT is untouched',
        (tester) async {
      cubit = newCubit();
      await declineTimes(tester, 1);
      await pump(tester, const KioskDeclinedScreen());

      // The charge did not happen, so this half stays.
      expect(
        find.textContaining('You haven\'t been charged'),
        findsOneWidget,
      );
      // The fresh card already replaced the payer's default (promoted before
      // charging; a decline reverts nothing), so the screen says so.
      expect(
        find.textContaining(
          'The card you entered is now the one saved on your profile',
        ),
        findsOneWidget,
      );
      // Absent on purpose: "everything else" reads as "the card too".
      expect(
        find.textContaining('everything else you filled in is saved'),
        findsNothing,
      );
      expect(
        find.widgetWithText(KioskPrimaryButton, 'Retry'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await cubit.close();
    });
  });

  group('E · the per-person results receipt', () {
    testWidgets('every membership created reads as a receipt with ONE Next, at '
        'either fold', (tester) async {
      for (final size in const [Size(1180, 820), Size(1024, 700)]) {
        await atGroupResults(
          tester,
          people: 5,
          landed: _multiResponse(const ['mem-1', 'mem-2', 'mem-3', 'mem-4',
            'mem-5']),
        );
        expect(cubit.state.step, KioskSignupStep.results);
        await pump(tester, const KioskResultsScreen(), size: size);

        expect(find.text('You\'re all set'), findsOneWidget);
        expect(find.text('Every membership below started today.'),
            findsOneWidget);
        expect(find.byType(FlowResultRow), findsNWidgets(5));
        expect(find.text('Marcus Bell · Unlimited'), findsOneWidget);
        expect(find.text('Started today'), findsNWidgets(5));
        // Names where FAILURE mail lands; no receipt is promised because none
        // is sent (see kiosk_money_panel_test.dart).
        expect(
          find.textContaining("we'll email you at marcus.bell@gmail.com"),
          findsOneWidget,
        );
        expect(find.textContaining('receipt'), findsNothing);
        // ONE advance, no escape: money has moved, so nothing to start over.
        expect(
          find.widgetWithText(KioskPrimaryButton, 'Next'),
          findsOneWidget,
        );
        expect(find.text('Start over'), findsNothing);
        expect(find.text('Retry the rest'), findsNothing);
        expect(find.byType(KioskReturnTimer), findsOneWidget);
        // The card chip is noise once the money has landed.
        expect(find.byType(FlowCardChip), findsNothing);
        expect(
          tester.takeException(),
          isNull,
          reason: 'the all-created receipt overflowed at $size',
        );
        await cubit.close();
      }
    });

    testWidgets('a PARTIAL carries the three decline actions AND the countdown, '
        'at either fold', (tester) async {
      for (final size in const [Size(1180, 820), Size(1024, 700)]) {
        await atGroupResults(
          tester,
          people: 5,
          landed: _multiResponse(
            const ['mem-1', 'mem-2', 'mem-3', 'mem-4', 'mem-5'],
            failed: const {'mem-4', 'mem-5'},
          ),
        );
        expect(cubit.state.step, KioskSignupStep.results);
        await pump(tester, const KioskResultsScreen(), size: size);

        expect(find.text('Some of these didn\'t go through'), findsOneWidget);
        expect(
          find.textContaining('The ones marked Started are paid for'),
          findsOneWidget,
        );
        expect(find.text('Started today'), findsNWidgets(3));
        expect(
          find.text('Not started — nothing was charged for this one.'),
          findsNWidgets(2),
        );
        expect(
          find.widgetWithText(KioskPrimaryButton, 'Retry the rest'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(KioskOutlineButton, 'Try another card'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(KioskOutlineButton, 'Get help at the desk'),
          findsOneWidget,
        );
        expect(find.byType(KioskReturnTimer), findsOneWidget);
        // Which card was used is the fact a member wants before retrying.
        expect(find.byType(FlowCardChip), findsOneWidget);
        // `Next` is live on a partial too (founder ruling): a retry-only
        // ladder strands a member who does not want to retry. It is
        // ADDITIONAL — the retry actions stay, and the desk finishes the rest.
        final next = tester.widget<KioskOutlineButton>(
          find.widgetWithText(KioskOutlineButton, 'Next'),
        );
        expect(next.onPressed, isNotNull);
        expect(
          find.textContaining('ask the front desk to finish the rest'),
          findsOneWidget,
        );
        expect(find.text('Start over'), findsNothing);
        expect(
          tester.takeException(),
          isNull,
          reason: 'the partial receipt overflowed at $size',
        );
        await cubit.close();
      }
    });

    testWidgets('a PARTIAL never lands on the decline popup — its copy would '
        'be false about money that moved', (tester) async {
      await atGroupResults(
        tester,
        people: 2,
        landed: _multiResponse(
          const ['mem-1', 'mem-2'],
          failed: const {'mem-2'},
        ),
      );

      // The bug guard. `KioskDeclinedScreen` states "You haven't been charged",
      // which is TRUE only when every item failed.
      expect(cubit.state.step, isNot(KioskSignupStep.declined));
      expect(cubit.state.step, KioskSignupStep.results);
      await cubit.close();
    });
  });
}

MembershipPlanResponse _plan() => MembershipPlanResponse(
      planId: 'plan-1',
      gymId: 'gym-1',
      planName: 'Unlimited',
      imageUrl: 'https://cdn/plan.png',
      planType: PlanType.recurring,
      durationAmount: 1,
      isPublic: true,
      createdAt: DateTime.utc(2026),
      waiverIds: const ['waiver-1'],
      activePrice: MembershipPlanPriceResponse(
        priceId: 'price-1',
        planId: 'plan-1',
        gymId: 'gym-1',
        stripePriceId: 'price_stripe',
        price: 14900,
        isActive: true,
        createdAt: DateTime.utc(2026),
      ),
    );

WaiverResponse _waiver() => WaiverResponse(
      waiverId: 'waiver-1',
      gymId: 'gym-1',
      name: 'Liability Waiver & Release',
      waiverType: WaiverType.custom,
      currentVersionId: 'ver-3',
      currentVersionNumber: 3,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      currentVersion: WaiverVersionResponse(
        versionId: 'ver-3',
        waiverId: 'waiver-1',
        gymId: 'gym-1',
        versionNumber: 3,
        body: 'I agree, {{signer_name}}.',
        contentHash: 'hash',
        createdAt: DateTime.utc(2026),
      ),
    );

PreviewInvoice _invoice(int total) => PreviewInvoice(
      amountDue: total,
      subtotal: total,
      total: total,
      currency: 'usd',
      lines: [
        PreviewInvoiceLine(
          amount: total,
          discountedAmount: total,
          description: 'Unlimited',
        ),
      ],
    );

MemberMembershipsStartPreview _preview() => MemberMembershipsStartPreview(
      dueNow: _invoice(14900),
      recurring: _invoice(14900),
    );

MemberMembershipsStartResponse _startResponse({bool failed = false}) =>
    MemberMembershipsStartResponse(
      chargeCount: 1,
      multipleCharges: false,
      results: [
        MemberMembershipsStartResultItem(
          memberId: 'mem-1',
          planId: 'plan-1',
          planType: PlanType.recurring,
          status: failed
              ? MemberMembershipsStartStatus.failed
              : MemberMembershipsStartStatus.created,
          itemId: failed ? null : 'item-1',
          error: failed ? 'card_declined' : null,
        ),
      ],
    );

/// One result item per member id, all on the same plan; ids in [failed] come
/// back refused, so a partial is a real mixed response.
MemberMembershipsStartResponse _multiResponse(
  List<String> memberIds, {
  Set<String> failed = const {},
}) =>
    MemberMembershipsStartResponse(
      chargeCount: 1,
      multipleCharges: false,
      results: [
        for (final id in memberIds)
          MemberMembershipsStartResultItem(
            memberId: id,
            planId: 'plan-1',
            planType: PlanType.recurring,
            status: failed.contains(id)
                ? MemberMembershipsStartStatus.failed
                : MemberMembershipsStartStatus.created,
            itemId: failed.contains(id) ? null : 'item-$id',
            error: failed.contains(id) ? 'card_declined' : null,
          ),
      ],
    );

CrmMembersListResponse _page(List<MemberRow> rows) => CrmMembersListResponse(
      view: MembersListView.all,
      filters: const MembersListFilters(),
      data: rows,
    );

/// A free trial beside the recurring plan, so "which card is marked used" is a
/// real assertion.
MembershipPlanResponse _trialPlan() => MembershipPlanResponse(
      planId: 'plan-trial',
      gymId: 'gym-1',
      planName: 'Two-week trial',
      imageUrl: '',
      planType: PlanType.trial,
      durationAmount: 2,
      isPublic: true,
      createdAt: DateTime.utc(2026),
      waiverIds: const ['waiver-1'],
      activePrice: MembershipPlanPriceResponse(
        priceId: 'price-trial',
        planId: 'plan-trial',
        gymId: 'gym-1',
        stripePriceId: 'price_stripe_trial',
        price: 0,
        isActive: true,
        createdAt: DateTime.utc(2026),
      ),
    );

/// A second recurring plan, so "a DIFFERENT one is still on offer" is a real
/// assertion rather than an absence.
MembershipPlanResponse _secondRecurringPlan() => MembershipPlanResponse(
      planId: 'plan-2',
      gymId: 'gym-1',
      planName: 'Two classes a week',
      imageUrl: '',
      planType: PlanType.recurring,
      durationAmount: 1,
      isPublic: true,
      createdAt: DateTime.utc(2026),
      waiverIds: const ['waiver-1'],
      activePrice: MembershipPlanPriceResponse(
        priceId: 'price-2',
        planId: 'plan-2',
        gymId: 'gym-1',
        stripePriceId: 'price_stripe_2',
        price: 6900,
        isActive: true,
        createdAt: DateTime.utc(2026),
      ),
    );

/// A member who currently HOLDS [planId] — an active membership of that type.
MemberDetailResponse _detailHolding(String planId, String planType) =>
    MemberDetailResponse(
      memberId: 'mem-old',
      gymId: 'gym-1',
      firstName: 'Marcus',
      lastName: 'Bell',
      membershipOverview: 'History',
      totalMonthlyRecurringPrice: 0,
      totalMembershipCount: 1,
      personalInfo: const PersonalInfo(),
      memberships: [
        MembershipInfo(
          planId: planId,
          planName: 'Unlimited',
          planType: planType,
          status: MembershipStatus.active,
          itemId: 'item-held',
          paidByMemberId: 'mem-old',
          baseCost: 14900,
          durationAmount: 1,
          durationUnit: 'month',
          totalPrice: 14900,
          startDate: DateTime.utc(2025),
        ),
      ],
      retention: const Retention(
        classStreakWeeks: 0,
        pointsBalance: 0,
        videosWatched: 0,
      ),
    );

/// A member whose history already holds a trial. The backend applies no
/// lifecycle filter to this list, so one taken and finished still counts.
MemberDetailResponse _detailWithTrial() => MemberDetailResponse(
      memberId: 'mem-old',
      gymId: 'gym-1',
      firstName: 'Marcus',
      lastName: 'Bell',
      membershipOverview: 'History',
      totalMonthlyRecurringPrice: 0,
      totalMembershipCount: 1,
      personalInfo: const PersonalInfo(),
      memberships: [
        MembershipInfo(
          planId: 'plan-trial',
          planName: 'Two-week trial',
          planType: 'trial',
          status: MembershipStatus.cancelled,
          itemId: 'item-trial',
          paidByMemberId: 'mem-old',
          baseCost: 0,
          durationAmount: 2,
          durationUnit: 'week',
          totalPrice: 0,
          startDate: DateTime.utc(2025),
        ),
      ],
      retention: const Retention(
        classStreakWeeks: 0,
        pointsBalance: 0,
        videosWatched: 0,
      ),
    );
