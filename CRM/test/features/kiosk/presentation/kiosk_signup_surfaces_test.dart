import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/kiosk/bloc/kiosk_session_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_section_head.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_card_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_declined_screen.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_name_row.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_payer_pick_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_people_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_plan_card.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_plan_pick_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_plan_picked_banner.dart';
import 'package:crm/features/member_details/data/models/authorized_payer_waiver.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_preview.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_response.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_result_item.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_status.dart';
import 'package:crm/features/member_details/data/models/member_payment_method_status.dart';
import 'package:crm/features/member_details/data/models/members_management_create_request.dart';
import 'package:crm/features/member_details/data/models/members_management_response.dart';
import 'package:crm/features/member_details/data/models/members_management_update_request.dart';
import 'package:crm/features/member_details/data/models/membership_plan_price_response.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/members_list/data/models/crm_members_list_request.dart';
import 'package:crm/features/members_list/data/models/crm_members_list_response.dart';
import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/features/members_list/data/models/members_list_filters.dart';
import 'package:crm/features/members_list/data/models/members_list_view.dart';
import 'package:crm/features/members_list/data/repositories/members_list_repository.dart';
import 'package:crm/features/member_details/presentation/dialogs/card_field_box.dart';
import 'package:crm/features/memberships/data/models/waiver_response.dart';
import 'package:crm/features/memberships/data/models/waiver_signature_response.dart';
import 'package:crm/features/memberships/data/models/waiver_type.dart';
import 'package:crm/features/memberships/data/models/waiver_version_response.dart';
import 'package:crm/features/memberships/data/repositories/memberships_repository.dart';

class _MockMemberRepository extends Mock implements MemberRepository {}

class _MockMembershipsRepository extends Mock
    implements MembershipsRepository {}

class _MockMembersListRepository extends Mock
    implements MembersListRepository {}

class _MockKioskSessionCubit extends Mock implements KioskSessionCubit {}

class _MockManagementResponse extends Mock
    implements MembersManagementResponse {}

class _MockSignatureResponse extends Mock implements WaiverSignatureResponse {}

/// The four surfaces the founder called out, rendered at the real fold
/// (1180x820): the payer picker's pickable rows read as controls, the payer is
/// deletable and its absence blocks the flow legibly, the plan pick confirms
/// the choice, and the decline is a popup whose timer is big — and whose
/// try-again returns to a genuinely fresh card field.
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
    when(() => member.getPaymentMethodStatus(any())).thenAnswer(
      (_) async => const MemberPaymentMethodStatus(hasPaymentMethod: false),
    );
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

    testWidgets('a decline returns to the card page and holds no timer',
        (tester) async {
      cubit = newCubit();
      await declineTimes(tester, 1);
      expect(cubit.state.retryCooldown, 0);
      await pump(tester, const KioskDeclinedScreen());

      expect(find.text('Your bank declined the payment'), findsOneWidget);
      expect(find.text('You can try again in'), findsNothing);
      // The natural action is enabled and goes back to the card page.
      final retry = tester.widget<KioskPrimaryButton>(
        find.widgetWithText(KioskPrimaryButton, 'Try another card'),
      );
      expect(retry.onPressed, isNotNull);
      final help = tester.widget<KioskOutlineButton>(
        find.widgetWithText(KioskOutlineButton, 'Get help at the desk'),
      );
      expect(help.onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      await cubit.close();
    });

    testWidgets('a cooldown shows the big timer and gates try-again',
        (tester) async {
      cubit = newCubit();
      await declineTimes(tester, 3);
      expect(cubit.state.retryCooldown, 30);
      await pump(tester, const KioskDeclinedScreen());

      // The wait is the popup's focus, not a buried button state.
      expect(find.text('You can try again in'), findsOneWidget);
      expect(find.text('30s'), findsOneWidget);
      // Try-again is gated; help is still open.
      final retry = tester.widget<KioskPrimaryButton>(
        find.widgetWithText(KioskPrimaryButton, 'Try another card'),
      );
      expect(retry.onPressed, isNull);
      final help = tester.widget<KioskOutlineButton>(
        find.widgetWithText(KioskOutlineButton, 'Get help at the desk'),
      );
      expect(help.onPressed, isNotNull);
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
