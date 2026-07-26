import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_cubit.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/data/models/discount_type.dart';
import 'package:crm/features/member_details/data/models/discount_value.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/plans/picked_membership_card.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/plans/plans_empty_body.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/plans_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_plan_card.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_quantity_stepper.dart';

import '../../../../../../shared/widgets/form/fake_network_images.dart';
import '../../../../bloc/membership_wizard/membership_wizard_fixtures.dart';
import 'wizard_step_harness.dart';

/// The plans step, rendered.
///
/// The catalogued defects it exists to fix: a gated plan was hidden (so nobody
/// learned why), the blocked mark read in the SUCCESS colour, and the
/// discounts lived on a step of their own — so two picked memberships could
/// not carry different ones.
void main() {
  late MockMemberRepository member;
  late MockMembershipsRepository memberships;
  late RecordedWizardActions recorded;

  final unlimited = plan(
    planId: 'plan-a',
    priceId: 'price-a',
    name: 'Unlimited Monthly',
  );
  final pack = plan(
    planId: 'plan-b',
    priceId: 'price-b',
    name: '5-Class Pack',
    type: PlanType.oneTime,
    price: 5000,
    classCount: 5,
  );
  final trial = plan(
    planId: 'plan-t',
    priceId: 'price-t',
    name: 'Two-Week Trial',
    type: PlanType.trial,
    price: 0,
  );

  final familyPreset = DiscountResponse(
    discountId: 'disc-family',
    gymId: kGymId,
    discountName: 'Family 20%',
    discountType: DiscountType.preset,
    valueId: 'val-1',
    value: const DiscountValue(percentageOff: 20),
    createdAt: DateTime.utc(2026),
  );

  setUpAll(registerWizardFallbacks);

  setUp(() {
    recorded = RecordedWizardActions();
    member = MockMemberRepository();
    memberships = MockMembershipsRepository();
    when(() => member.listMembershipPlans(any()))
        .thenAnswer((_) async => [unlimited, pack, trial]);
    when(() => member.listGymDiscounts(any()))
        .thenAnswer((_) async => [familyPreset]);
    when(() => memberships.listMemberWaiverStatus(any(), any()))
        .thenAnswer((_) async => []);
  });

  /// Marcus alone, standing on his own plans step.
  Future<MembershipWizardCubit> atPlans({
    List<MembershipInfo> held = const [],
  }) async {
    final cubit = buildWizard(
      member: member,
      memberships: memberships,
      launchMember: detail(memberships: held),
    );
    await cubit.open();
    await cubit.next();
    return cubit;
  }

  Future<void> pumpStep(
    WidgetTester tester,
    MembershipWizardCubit cubit,
  ) =>
      pumpWizardStep(
        tester,
        cubit: cubit,
        step: WizardPlansStep(
          showAddMemberGroup: false,
          actions: recorded.actions,
        ),
      );

  Finder cardFor(String planName) => find.ancestor(
        of: find.text(planName),
        matching: find.byType(FlowPlanCard),
      );

  testWidgets('a recurring plan the person already holds renders BLOCKED, '
      'tagged with the gate\'s own reason', (tester) async {
    await withFakeNetworkImages(() async {
      final cubit = await atPlans(held: [held(planId: 'plan-a')]);
      await pumpStep(tester, cubit);

      expect(
        find.byType(FlowPlanCard),
        findsNWidgets(3),
        reason: 'blocked, never hidden — a hidden card teaches nobody why',
      );
      expect(
        tester.widget<FlowPlanCard>(cardFor('Unlimited Monthly')).blocked,
        isTrue,
      );
      expect(find.text('Already on this plan'), findsOneWidget);
      expect(
        find.text(staffCopy.planBlockedTag),
        findsNothing,
        reason: 'the gate names itself; the fallback word is for callers with '
            'no gate',
      );
      await cubit.close();
    });
  });

  testWidgets('the blocked reason is NOT painted in the success colour',
      (tester) async {
    await withFakeNetworkImages(() async {
      final cubit = await atPlans(held: [held(planId: 'plan-a')]);
      await pumpStep(tester, cubit);

      final tag = tester.widget<Text>(find.text('Already on this plan'));
      expect(tag.style?.color, isNotNull);
      expect(
        tag.style!.color,
        isNot(DesignConstants.goodGreen),
        reason: 'a "you cannot sell this" in the success green is the '
            'catalogued defect',
      );
      expect(tag.style!.color, DesignConstants.text);
      await cubit.close();
    });
  });

  testWidgets('tapping a blocked card EXPLAINS rather than selecting',
      (tester) async {
    await withFakeNetworkImages(() async {
      final cubit = await atPlans(held: [held(planId: 'plan-a')]);
      await pumpStep(tester, cubit);

      await tester.tap(cardFor('Unlimited Monthly'));
      await tester.pumpAndSettle();

      expect(
        find.text(WizardPlansCopy.blockedNote('Marcus', 'Unlimited Monthly')),
        findsOneWidget,
      );
      expect(cubit.state.currentDrafts, isEmpty);
      expect(find.byType(PickedMembershipCard), findsNothing);
      await cubit.close();
    });
  });

  testWidgets('a repeat trial is a NOTE, not a gate — and can still be picked',
      (tester) async {
    await withFakeNetworkImages(() async {
      final cubit = await atPlans(
        held: [
          held(
            planId: 'plan-t',
            planType: 'trial',
            status: MembershipStatus.ended,
          ),
        ],
      );
      await pumpStep(tester, cubit);

      expect(tester.widget<FlowPlanCard>(cardFor('Two-Week Trial')).blocked,
          isFalse);
      expect(find.text('Had this trial in the past'), findsOneWidget);

      await tester.tap(cardFor('Two-Week Trial'));
      await tester.pumpAndSettle();

      expect(cubit.state.currentDrafts.single.plan.planId, 'plan-t');
      expect(find.byType(PickedMembershipCard), findsOneWidget);
      await cubit.close();
    });
  });

  testWidgets('two picked plans are two cards, and a discount added to one '
      'does not reach the other', (tester) async {
    await withFakeNetworkImages(() async {
      final cubit = await atPlans();
      cubit.togglePlan(unlimited);
      cubit.togglePlan(pack);
      await pumpStep(tester, cubit);

      expect(find.byType(PickedMembershipCard), findsNWidgets(2));
      expect(find.text('MEMBERSHIP 1 OF 2'), findsOneWidget);
      expect(find.text('MEMBERSHIP 2 OF 2'), findsOneWidget);

      cubit.togglePresetDiscount('plan-a', 'disc-family');
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(PickedMembershipCard).at(0),
          matching: find.text('Family 20%'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(PickedMembershipCard).at(1),
          matching: find.text('Family 20%'),
        ),
        findsNothing,
        reason: 'discounts attach per MEMBERSHIP, never per member',
      );
      await cubit.close();
    });
  });

  testWidgets('the pack stepper is on a one-time membership and ABSENT on a '
      'recurring one', (tester) async {
    await withFakeNetworkImages(() async {
      final cubit = await atPlans();
      cubit.togglePlan(pack);
      await pumpStep(tester, cubit);

      expect(find.byType(FlowQuantityStepper), findsOneWidget);
      expect(find.text(WizardPlansCopy.packsLabel), findsOneWidget);

      cubit.togglePlan(pack);
      cubit.togglePlan(unlimited);
      await tester.pumpAndSettle();

      expect(find.byType(PickedMembershipCard), findsOneWidget);
      expect(
        find.byType(FlowQuantityStepper),
        findsNothing,
        reason: 'a DB trigger pins recurring to one unit, so the control is '
            'absent rather than disabled',
      );
      await cubit.close();
    });
  });

  testWidgets('a gym with no purchasable plans gets the empty state and a '
      'closed primary', (tester) async {
    when(() => member.listMembershipPlans(any())).thenAnswer((_) async => []);
    final cubit = await atPlans();
    await pumpStep(tester, cubit);

    expect(find.byType(PlansEmptyBody), findsOneWidget);
    expect(find.text(WizardPlansCopy.noPlansTitle), findsOneWidget);
    expect(find.text(WizardPlansCopy.noPlansFoot), findsOneWidget);
    expect(wizardPrimary(tester, staffCopy.continueAction).onPressed, isNull);
    await cubit.close();
  });

  testWidgets('a failed catalogue read offers the retry, and Try again reads '
      'again', (tester) async {
    when(() => member.listMembershipPlans(any()))
        .thenAnswer((_) async => throw Exception('catalogue down'));
    final cubit = await atPlans();
    await pumpStep(tester, cubit);

    expect(find.byType(PlansEmptyBody), findsNothing);
    expect(find.text(WizardPlansCopy.plansFailedTitle), findsOneWidget);
    expect(find.text(WizardPlansCopy.plansFailedFoot), findsOneWidget);

    await tester.tap(find.text(staffCopy.retryAction));
    await tester.pumpAndSettle();

    verify(() => member.listMembershipPlans(any())).called(2);
    await cubit.close();
  });
}
