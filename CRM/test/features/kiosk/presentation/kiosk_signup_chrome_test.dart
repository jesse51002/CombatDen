import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/kiosk/bloc/kiosk_session_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/presentation/kiosk_rail_index.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_card_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_plan_pick_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_review_step.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_waiver_step.dart';
import 'package:crm/features/member_details/data/models/authorized_payer_waiver.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_preview.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_request.dart';
import 'package:crm/features/member_details/data/models/members_management_create_request.dart';
import 'package:crm/features/member_details/data/models/members_management_response.dart';
import 'package:crm/features/member_details/data/models/members_management_update_request.dart';
import 'package:crm/features/member_details/data/models/membership_plan_price_response.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/features/members_list/data/repositories/members_list_repository.dart';
import 'package:crm/features/membership_flow/config/kiosk_flow_copy.dart';
import 'package:crm/features/membership_flow/config/membership_flow_scale.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_who_for.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_plan_card.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_proration_note.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_waiver_doc_panel.dart';
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

/// The signup chrome: who a step is FOR, and whether it stays on screen.
///
/// On the plan and waiver steps the answer is the ACTIVE person; on the card
/// step it is the PAYER, who in a family is somebody else entirely — naming
/// the child over a field that attaches a card to the parent's profile would
/// be confidently wrong. Layout at both folds is asserted, never assumed.
void main() {
  late KioskSignupCubit cubit;
  late _MockMemberRepository member;
  late _MockMembershipsRepository memberships;
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
    when(() => memberships.listPlans(any()))
        .thenAnswer((_) async => [_plan('plan-1', 'Unlimited')]);
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
  });

  /// Built inside the TEST BODY, never `setUp`: the constructor warms the plan
  /// catalogue, and a future started in the enclosing zone is not drained by
  /// the widget test's fake clock.
  KioskSignupCubit newCubit() => KioskSignupCubit(
        memberRepository: member,
        membershipsRepository: memberships,
        membersListRepository: _MockMembersListRepository(),
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
          copy: const KioskFlowCopy(),
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

  /// The payer, created, standing on the roster.
  Future<void> createPayer() async {
    cubit = newCubit();
    cubit.submitDetails(
      firstName: 'Marcus',
      lastName: 'Bell',
      email: 'marcus.bell@gmail.com',
    );
    await cubit.submitExtraDetails();
  }

  /// Add a second person, so the flow is a GROUP.
  Future<void> addElla() async {
    await cubit.addPerson(
      firstName: 'Ella',
      lastName: 'Bell',
      email: 'ella.bell@gmail.com',
    );
    cubit.skipPersonDetails();
  }

  group('the plan step names who it is for', () {
    testWidgets('a group names EVERY person, the payer included',
        (tester) async {
      await createPayer();
      await addElla();
      cubit.continueToPlans();
      await pump(tester, const KioskPlanPickStep());

      expect(cubit.state.activePersonIndex, 0);
      expect(find.text('Pick Marcus\'s membership'), findsOneWidget);
      expect(find.text('Pick your membership'), findsNothing);
      expect(find.byType(FlowWhoFor), findsOneWidget);
      expect(find.text('PICKING FOR'), findsOneWidget);
      expect(find.text('Marcus Bell'), findsOneWidget);

      cubit.selectPlan('plan-1');
      cubit.continueFromPlans();
      // Two emits in one tick: the pick, then the hand-over to the next person.
      await tester.pump();
      await tester.pump();
      expect(find.text('Pick Ella\'s membership'), findsOneWidget);
      expect(find.text('Ella Bell'), findsOneWidget);
      await cubit.close();
    });

    testWidgets('a SOLO signup keeps the warm second person', (tester) async {
      await createPayer();
      cubit.continueToPlans();
      await pump(tester, const KioskPlanPickStep());

      expect(find.text('Pick your membership'), findsOneWidget);
      expect(find.text('Pick Marcus\'s membership'), findsNothing);
      // Nobody to disambiguate from, so no strip either.
      expect(find.byType(FlowWhoFor), findsNothing);
      await cubit.close();
    });

    testWidgets('the GROUP rail scales instead of clipping on a short fold',
        (tester) async {
      // A clipped rail loses exactly the rungs not reached yet — the half that
      // says how much is left — so the 7-rung group template scales instead.
      for (final size in const [Size(1180, 820), Size(1024, 700)]) {
        await createPayer();
        await addElla();
        cubit.continueToPlans();
        await pump(tester, const KioskPlanPickStep(), size: size);

        for (final label in kKioskGroupSteps) {
          expect(find.text(label), findsOneWidget, reason: '$label at $size');
        }
        expect(
          tester.takeException(),
          isNull,
          reason: 'the step rail overflowed at $size',
        );
        await cubit.close();
      }
    });

    testWidgets('the identity stays put while the plan grid scrolls',
        (tester) async {
      when(() => memberships.listPlans(any())).thenAnswer(
        (_) async => [
          for (var i = 1; i <= 12; i++) _plan('plan-$i', 'Plan $i'),
        ],
      );
      await createPayer();
      await addElla();
      cubit.continueToPlans();
      await pump(tester, const KioskPlanPickStep());
      expect(find.byType(FlowPlanCard), findsWidgets);

      await tester.drag(
        find.byType(FlowPlanCard).first,
        const Offset(0, -600),
      );
      await tester.pump();

      expect(find.byType(FlowWhoFor), findsOneWidget);
      expect(find.text('Marcus Bell'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await cubit.close();
    });
  });

  group('the waiver step', () {
    /// Walk a two-person group to the payer's OWN liability waiver.
    Future<void> atPayerWaiver(WidgetTester tester) async {
      await createPayer();
      await addElla();
      cubit.continueToPlans();
      cubit.selectPlan('plan-1');
      cubit.continueFromPlans();
      cubit.selectPlan('plan-1');
      cubit.continueFromPlans();
      await tester.pump();
      await cubit.signPayerAuth(signerName: 'Marcus Bell');
      await tester.pump();
      // Ella's own waiver, then Marcus's.
      await cubit.signWaiver(signerName: 'Marcus Bell');
      await tester.pump();
    }

    testWidgets('names the person and pins them over the document',
        (tester) async {
      await atPayerWaiver(tester);
      await pump(tester, const KioskWaiverStep());

      expect(cubit.state.activePersonIndex, 0);
      expect(find.text('Marcus\'s waiver'), findsOneWidget);
      expect(find.byType(FlowWhoFor), findsOneWidget);
      expect(find.text('WAIVER FOR'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await cubit.close();
    });

    testWidgets('the reading box fills the fold instead of a dialog height',
        (tester) async {
      await atPayerWaiver(tester);
      await pump(tester, const KioskWaiverStep());

      // The document panel takes the fold, not an admin dialog's 240px box.
      final panel = tester.getSize(find.byType(FlowWaiverDocPanel));
      expect(panel.height, greaterThan(320));
      expect(tester.takeException(), isNull);
      await cubit.close();
    });

    testWidgets('a LONG document scrolls inside the panel, not the step',
        (tester) async {
      when(() => memberships.getWaiver(any(), any()))
          .thenAnswer((_) async => _waiver(body: _longBody));
      await atPayerWaiver(tester);
      await pump(tester, const KioskWaiverStep());

      // The footer is still on the fold — a long body cannot push it away.
      expect(find.text('Sign and continue'), findsOneWidget);
      expect(find.byType(FlowWhoFor), findsOneWidget);
      expect(tester.takeException(), isNull);
      await cubit.close();
    });
  });

  group('the card step names the PAYER, never the active person', () {
    testWidgets('a group shows the payer even when someone else is active',
        (tester) async {
      await createPayer();
      await addElla();
      cubit.continueToPlans();
      cubit.selectPlan('plan-1');
      // Walking on makes the CHILD the active person — the inverted case.
      cubit.continueFromPlans();
      cubit.selectPlan('plan-1');
      expect(cubit.state.activePerson.firstName, 'Ella');
      expect(cubit.state.cartHasRecurring, isTrue);
      await pump(tester, const KioskCardStep());

      expect(find.text('CARD FOR'), findsOneWidget);
      expect(find.text('Marcus Bell'), findsOneWidget);
      expect(find.text('Ella Bell'), findsNothing);
      expect(
        find.textContaining(
          'This card is saved to Marcus Bell\'s profile',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('It replaces any card already on file.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await cubit.close();
    });

    testWidgets('an ADOPTED existing payer is the name on the promise',
        (tester) async {
      await createPayer();
      cubit.openPayerPick();
      await cubit.pickPayerRow(
        AllViewRow(
          memberId: 'mem-dad',
          name: 'Rick Bell',
          email: 'rick.bell@gmail.com',
          membershipStatus: MembershipStatus.active,
          membershipText: 'Monthly',
        ),
      );
      expect(cubit.state.payer.wasExisting, isTrue);
      cubit.selectPlan('plan-1');
      await pump(tester, const KioskCardStep());

      expect(find.text('CARD FOR'), findsOneWidget);
      expect(find.text('Rick Bell'), findsOneWidget);
      // The person standing there is NOT the profile the card lands on.
      expect(find.text('Marcus Bell'), findsNothing);
      expect(tester.takeException(), isNull);
      await cubit.close();
    });
  });

  group('the review explains a part-period charge', () {
    /// Solo, at the review, with [preview] staged.
    Future<void> atReview(
      WidgetTester tester,
      MemberMembershipsStartPreview preview,
    ) async {
      when(() => member.previewStartMemberships(any()))
          .thenAnswer((_) async => preview);
      await createPayer();
      cubit.continueToPlans();
      cubit.selectPlan('plan-1');
      cubit.continueFromPlans();
      await tester.pump();
      await cubit.signWaiver(signerName: 'Marcus Bell');
      await tester.pump();
      cubit.submitCard(paymentMethodId: 'pm_1', brand: 'visa', last4: '4242');
      await tester.pump();
    }

    testWidgets('a PRORATED preview says so, and names the date',
        (tester) async {
      await atReview(tester, _prorated());
      await pump(tester, const KioskReviewStep());

      expect(find.byType(FlowProrationNote), findsOneWidget);
      // Derived from the preview's own `next_payment_date`, rendered local,
      // rather than hard-coded against whatever zone the suite runs in.
      expect(
        find.textContaining('covers you up to $_anchorLabel'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await cubit.close();
    });

    testWidgets('a NON-prorated preview says nothing about proration',
        (tester) async {
      await atReview(tester, _plain());
      await pump(tester, const KioskReviewStep());

      expect(find.byType(FlowProrationNote), findsNothing);
      expect(find.textContaining('part-period'), findsNothing);
      expect(tester.takeException(), isNull);
      await cubit.close();
    });

    testWidgets('it composes with the two-charges note without arguing',
        (tester) async {
      await atReview(tester, _proratedPlusOneTime());
      await pump(tester, const KioskReviewStep());

      expect(find.byType(FlowProrationNote), findsOneWidget);
      expect(
        find.textContaining('two separate charges today'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await cubit.close();
    });
  });

  group('the committing CTA reads by plan type, and still fits', () {
    /// Solo, at the review, on a cart of [type] costing [price] today.
    Future<void> atReviewWith(
      WidgetTester tester, {
      required PlanType type,
      required int price,
    }) async {
      when(() => memberships.listPlans(any()))
          .thenAnswer((_) async => [_plan('plan-1', 'Unlimited', type: type)]);
      when(() => member.previewStartMemberships(any()))
          .thenAnswer((_) async => _invoiceOnly(price));
      await createPayer();
      cubit.continueToPlans();
      cubit.selectPlan('plan-1');
      cubit.continueFromPlans();
      await tester.pump();
      await cubit.signWaiver(signerName: 'Marcus Bell');
      await tester.pump();
      cubit.submitCard(paymentMethodId: 'pm_1', brand: 'visa', last4: '4242');
      await tester.pump();
    }

    testWidgets('a paid membership reads "Sign Membership · amount"',
        (tester) async {
      await atReviewWith(tester, type: PlanType.recurring, price: 14900);
      await pump(tester, const KioskReviewStep());

      expect(find.text('Sign Membership · \$149.00'), findsOneWidget);
      // The button never says "Pay", so the subtitle cannot name it.
      expect(find.textContaining('until you tap Pay'), findsNothing);
      expect(
        find.text('Nothing is charged until you confirm.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await cubit.close();
    });

    testWidgets('a PAID trial keeps its amount — a trial is a category, not '
        'a price', (tester) async {
      await atReviewWith(tester, type: PlanType.trial, price: 2000);
      await pump(tester, const KioskReviewStep());

      expect(find.text('Sign Trial · \$20.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await cubit.close();
    });

    testWidgets('a FREE trial collapses to the bare verb, never "\$0.00"',
        (tester) async {
      await atReviewWith(tester, type: PlanType.trial, price: 0);
      await pump(tester, const KioskReviewStep());

      // Only the BUTTON collapses; the money panel still states \$0.00.
      expect(find.text('Sign Trial'), findsOneWidget);
      expect(find.text('Sign Trial · \$0.00'), findsNothing);
      expect(tester.takeException(), isNull);
      await cubit.close();
    });

    testWidgets('the LONGEST label does not overflow the foot at either fold',
        (tester) async {
      for (final size in const [Size(1180, 820), Size(1024, 700)]) {
        await atReviewWith(tester, type: PlanType.recurring, price: 14900);
        await pump(tester, const KioskReviewStep(), size: size);

        expect(find.text('Sign Membership · \$149.00'), findsOneWidget);
        expect(find.text('Back'), findsOneWidget);
        expect(find.text('Start over'), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: 'the signup foot overflowed at $size',
        );
        await cubit.close();
      }
    });
  });
}

const String _longBody = 'A very long agreement. '
    'Paragraph one about the risks of training here and everything that '
    'follows from it. '
    'Paragraph two about the risks of training here and everything that '
    'follows from it. '
    'Paragraph three about the risks of training here and everything that '
    'follows from it. '
    'Paragraph four about the risks of training here and everything that '
    'follows from it. '
    'Paragraph five about the risks of training here and everything that '
    'follows from it. '
    'Paragraph six about the risks of training here and everything that '
    'follows from it. '
    'I agree, {{signer_name}}.';

MembershipPlanResponse _plan(
  String id,
  String name, {
  PlanType type = PlanType.recurring,
}) =>
    MembershipPlanResponse(
      planId: id,
      gymId: 'gym-1',
      planName: name,
      imageUrl: '',
      planType: type,
      durationAmount: 1,
      isPublic: true,
      createdAt: DateTime.utc(2026),
      waiverIds: const ['waiver-1'],
      activePrice: MembershipPlanPriceResponse(
        priceId: 'price-$id',
        planId: id,
        gymId: 'gym-1',
        stripePriceId: 'price_stripe_$id',
        price: 14900,
        isActive: true,
        createdAt: DateTime.utc(2026),
      ),
    );

WaiverResponse _waiver({String body = 'I agree, {{signer_name}}.'}) =>
    WaiverResponse(
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
        body: body,
        contentHash: 'hash',
        createdAt: DateTime.utc(2026),
      ),
    );

/// 1 February 2026, 12:00 UTC — the anchor every proration test names.
const int _anchorEpoch = 1769947200;

/// How that instant reads on the screen, in whatever zone the suite runs in.
final String _anchorLabel = DateFormat('d MMMM y').format(
  DateTime.fromMillisecondsSinceEpoch(_anchorEpoch * 1000, isUtc: true)
      .toLocal(),
);

PreviewInvoice _invoice(
  int total, {
  bool proration = false,
  int? nextPaymentDate,
}) =>
    PreviewInvoice(
      amountDue: total,
      subtotal: total,
      total: total,
      currency: 'usd',
      nextPaymentDate: nextPaymentDate,
      lines: [
        PreviewInvoiceLine(
          amount: total,
          discountedAmount: total,
          description: 'Membership',
          stripePriceId: 'price_stripe_plan-1',
          isProration: proration,
        ),
      ],
    );

MemberMembershipsStartPreview _prorated() => MemberMembershipsStartPreview(
      dueNow: _invoice(4800, proration: true, nextPaymentDate: _anchorEpoch),
      recurring: _invoice(14900, nextPaymentDate: _anchorEpoch),
    );

MemberMembershipsStartPreview _plain() => MemberMembershipsStartPreview(
      dueNow: _invoice(14900, nextPaymentDate: _anchorEpoch),
      recurring: _invoice(14900, nextPaymentDate: _anchorEpoch),
    );

MemberMembershipsStartPreview _proratedPlusOneTime() =>
    MemberMembershipsStartPreview(
      oneTime: _invoice(3500),
      dueNow: _invoice(4800, proration: true, nextPaymentDate: _anchorEpoch),
      recurring: _invoice(14900, nextPaymentDate: _anchorEpoch),
    );

/// One invoice due today, nothing recurring — the shape the CTA's amount is
/// read off.
MemberMembershipsStartPreview _invoiceOnly(int total) =>
    MemberMembershipsStartPreview(dueNow: _invoice(total));
