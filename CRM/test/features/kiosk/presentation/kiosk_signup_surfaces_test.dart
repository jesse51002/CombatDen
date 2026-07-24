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
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_plan_card.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_plan_pick_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_plan_picked_banner.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_trial_block.dart';
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
import 'package:crm/features/members_list/data/models/crm_members_list_request.dart';
import 'package:crm/features/members_list/data/models/crm_members_list_response.dart';
import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/features/members_list/data/models/members_list_filters.dart';
import 'package:crm/features/members_list/data/models/members_list_view.dart';
import 'package:crm/features/members_list/data/repositories/members_list_repository.dart';
import 'package:crm/features/member_details/presentation/dialogs/card_field_box.dart';
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

/// The surfaces the founder called out, rendered at the real fold: the lane's
/// front door offers both ways in and the identify search stays avatar-free,
/// the payer picker's pickable rows read as controls, the payer is deletable
/// and its absence blocks the flow legibly, the plan pick confirms the choice
/// and marks a used trial, and the decline is a popup that stacks three live
/// actions (Retry the same card, Try another card, Get help) over a visible
/// return countdown, without overflow.
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

  /// Walk a solo signup to the review, then decline the charge [times] times.
  ///
  /// Uses `tester.pump()` (never `Future.delayed`) to flush the cubit's
  /// unawaited reads — under the widget test's fake clock a zero-duration timer
  /// never fires without a pump, so `Future.delayed(Duration.zero)` would hang.
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
      // **A shared lobby iPad never prints a face or an address here.** The
      // masked email belongs to the confirm card, one step later.
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

      // Ella is offered as ONE affordant row — contained, with a chevron —
      // never a bare centred line.
      expect(find.byType(KioskNameRow), findsOneWidget);
      expect(find.byIcon(Symbols.chevron_right_sharp), findsWidgets);
      // The section heads are the quiet variant (they still name the sections).
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

      // Both the payer and the payee can be removed.
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
      // Continue is disabled — and never a dead button, the reason is beside it.
      final primary = tester.widget<KioskPrimaryButton>(
        find.byType(KioskPrimaryButton),
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

      // No current payer to name, and the remaining person is selectable.
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

      // No confirmation until something is picked.
      expect(find.byType(KioskPlanPickedBanner), findsNothing);

      await tester.tap(find.byType(KioskPlanCard).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(KioskPlanPickedBanner), findsOneWidget);
      expect(find.text('YOU\'VE PICKED'), findsOneWidget);
      // The plan is named (in the banner and on the card).
      expect(find.text('Unlimited'), findsWidgets);
      expect(tester.takeException(), isNull);
      await cubit.close();
    });

    testWidgets('a trial the member has already had renders USED and explains '
        'instead of selecting', (tester) async {
      when(() => memberships.listPlans(any()))
          .thenAnswer((_) async => [_plan(), _trialPlan()]);
      when(() => member.getMemberDetail(any()))
          .thenAnswer((_) async => _detailWithTrial());
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
      await pump(tester, const KioskPlanPickStep());

      // The card wears its mark before anybody taps it.
      expect(find.text('Already used'), findsOneWidget);

      await tester.tap(find.widgetWithText(KioskPlanCard, 'Two-week trial'));
      await tester.pump();
      // The tap EXPLAINS and selects nothing — a blocked plan can never reach
      // the review and fail at pay, and a greyed-out card with no answer is a
      // worse dead end than the one it prevents.
      expect(cubit.state.activePerson.selectedPlanId, isNull);
      expect(cubit.state.trialBlockActive, isTrue);
      expect(find.byType(KioskPlanPickedBanner), findsNothing);
      expect(tester.takeException(), isNull);
      await cubit.close();
    });

    testWidgets('the trial popup carries its countdown and both ways out at '
        'either fold', (tester) async {
      for (final size in const [Size(1180, 820), Size(1024, 700)]) {
        cubit = newCubit();
        await pump(tester, const KioskTrialBlock(), size: size);

        expect(find.text('You\'ve already had a trial'), findsOneWidget);
        expect(
          find.textContaining('Trials are one to a member'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(KioskPrimaryButton, 'Pick a membership'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(KioskOutlineButton, 'Get help at the desk'),
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
  });

  group('D · the card field and the decline popup', () {
    testWidgets('the card field is re-keyed per attempt', (tester) async {
      cubit = newCubit();
      await pump(tester, const KioskCardStep());

      final key0 =
          tester.widget<CardFieldBox>(find.byType(CardFieldBox)).fieldKey;
      expect(key0, const ValueKey('kiosk-card-0'));

      // A retry mounts a brand-new field identity. The emit reaches the
      // builder on a microtask, so the frame after it carries the change.
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
      // **The countdown is a RETURN clock, not a cooldown.** It says how long
      // a shared iPad may sit here unanswered; it never gates Retry, and
      // there is no "you can try again in" anywhere.
      expect(find.byType(KioskReturnTimer), findsOneWidget);
      expect(
        find.text('Back to start in ${kKioskSignupPopupHold.inSeconds}s'),
        findsOneWidget,
      );
      expect(find.textContaining('You can try again in'), findsNothing);

      // Retry (the primary) re-attempts the SAME card; the two secondaries are
      // "Try another card" and the desk handoff. All three are live from the
      // first frame — no cooldown, no attempt cap.
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
      // Three stacked buttons plus the countdown at the real fold (1180x820)
      // must not overflow.
      expect(tester.takeException(), isNull);
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

CrmMembersListResponse _page(List<MemberRow> rows) => CrmMembersListResponse(
      view: MembersListView.all,
      filters: const MembersListFilters(),
      data: rows,
    );

/// A free trial, beside the recurring plan, so "which card is marked used" is a
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
