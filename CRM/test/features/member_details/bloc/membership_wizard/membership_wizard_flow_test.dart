import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_cubit.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_step.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';

import 'membership_wizard_fixtures.dart';

/// The staff flow's NAVIGATION — the per-person plans loop, the conditional
/// waiver step, edit-from-review, and the back move the old wizard got wrong.
void main() {
  late MockMemberRepository member;
  late MockMembershipsRepository memberships;

  final soloPlan = plan(planId: 'plan-solo', priceId: 'price-solo');
  final packPlan = plan(
    planId: 'plan-pack',
    priceId: 'price-pack',
    type: PlanType.oneTime,
    classCount: 5,
  );

  setUpAll(registerWizardFallbacks);

  setUp(() {
    member = MockMemberRepository();
    memberships = MockMembershipsRepository();
    when(() => member.listMembershipPlans(any()))
        .thenAnswer((_) async => [soloPlan, packPlan]);
    when(() => member.listGymDiscounts(any())).thenAnswer((_) async => []);
    when(() => member.previewStartMemberships(any()))
        .thenAnswer((_) async => startPreview(recurring: invoice()));
    when(() => memberships.listMemberWaiverStatus(any(), any()))
        .thenAnswer((_) async => []);
  });

  /// A payer with one child, both ticked, plans loaded.
  Future<MembershipWizardCubit> family() async {
    final child = linked(memberId: 'm-child', firstName: 'Ella');
    final launch = detail(authorizedToPayFor: [child]);
    when(() => member.getMemberDetail('m-child'))
        .thenAnswer((_) async => detail(memberId: 'm-child', firstName: 'Ella'));
    final cubit = buildWizard(
      member: member,
      memberships: memberships,
      launchMember: launch,
      initialTrainingMemberIds: const {'m-payer', 'm-child'},
    );
    await cubit.open();
    return cubit;
  }

  test('walks the plans step once per training person', () async {
    final cubit = await family();
    expect(cubit.state.trainingPeople.length, 2);
    expect(cubit.state.stepCount, 6, reason: '4 + N with nothing to sign');

    await cubit.next();
    expect(cubit.state.step, MembershipWizardStep.plans);
    expect(cubit.state.currentPerson?.memberId, 'm-payer');

    // Next is refused while this person has picked nothing — an empty lineup
    // would send a member with no membership into the loop.
    await cubit.next();
    expect(cubit.state.currentPerson?.memberId, 'm-payer');

    cubit.togglePlan(soloPlan);
    await cubit.next();
    expect(cubit.state.currentPerson?.memberId, 'm-child');

    cubit.togglePlan(packPlan);
    await cubit.next();
    expect(cubit.state.step, MembershipWizardStep.reviewCharges);
    await cubit.close();
  });

  test('skips the waiver step when no picked plan requires a signature',
      () async {
    final cubit = await family();
    await cubit.next();
    cubit.togglePlan(soloPlan);
    await cubit.next();
    cubit.togglePlan(packPlan);
    await cubit.next();
    expect(cubit.state.hasWaivers, isFalse);
    expect(cubit.state.step, MembershipWizardStep.reviewCharges);
    expect(cubit.state.steps, isNot(contains(MembershipWizardStep.waivers)));
    await cubit.close();
  });

  test('back from the review lands on the LAST training person, not a stale '
      'index', () async {
    final cubit = await family();
    await cubit.next();
    cubit.togglePlan(soloPlan);
    await cubit.next();
    cubit.togglePlan(packPlan);
    await cubit.next();
    expect(cubit.state.step, MembershipWizardStep.reviewCharges);

    // The roster shrinks while staff are on the review — the exact case the
    // old wizard's remembered index could not survive.
    cubit.removeMembership('m-child', packPlan.planId);
    expect(cubit.state.trainingPeople.length, 1);

    await cubit.back();
    expect(cubit.state.step, MembershipWizardStep.plans);
    expect(cubit.state.personIndex, 0);
    expect(cubit.state.currentPerson?.memberId, 'm-payer');
    await cubit.close();
  });

  test('editing one person from the review returns straight to the review',
      () async {
    final cubit = await family();
    await cubit.next();
    cubit.togglePlan(soloPlan);
    await cubit.next();
    cubit.togglePlan(packPlan);
    await cubit.next();

    cubit.editFromReview('m-payer');
    expect(cubit.state.step, MembershipWizardStep.plans);
    expect(cubit.state.personIndex, 0);
    expect(cubit.state.editReturnsToReview, isTrue);

    await cubit.next();
    expect(
      cubit.state.step,
      MembershipWizardStep.reviewCharges,
      reason: 'an edit does not walk on to the next person',
    );
    expect(cubit.state.editReturnsToReview, isFalse);
    await cubit.close();
  });

  test('back mid-edit abandons the edit and re-prices the review', () async {
    final cubit = await family();
    await cubit.next();
    cubit.togglePlan(soloPlan);
    await cubit.next();
    cubit.togglePlan(packPlan);
    await cubit.next();

    cubit.editFromReview('m-child');
    await cubit.back();
    expect(cubit.state.step, MembershipWizardStep.reviewCharges);
    expect(cubit.state.editReturnsToReview, isFalse);
    await cubit.close();
  });

  test('back walks the plans loop one person at a time, then to who',
      () async {
    final cubit = await family();
    await cubit.next();
    cubit.togglePlan(soloPlan);
    await cubit.next();
    expect(cubit.state.personIndex, 1);

    await cubit.back();
    expect(cubit.state.step, MembershipWizardStep.plans);
    expect(cubit.state.personIndex, 0);

    await cubit.back();
    expect(cubit.state.step, MembershipWizardStep.who);

    // The first step has nowhere to go back to.
    await cubit.back();
    expect(cubit.state.step, MembershipWizardStep.who);
    await cubit.close();
  });

  test('back from payment re-enters the review and re-prices it', () async {
    final cubit = await family();
    await cubit.next();
    cubit.togglePlan(soloPlan);
    await cubit.next();
    cubit.togglePlan(packPlan);
    await cubit.next();
    await cubit.next();
    expect(cubit.state.step, MembershipWizardStep.payment);

    await cubit.back();
    expect(cubit.state.step, MembershipWizardStep.reviewCharges);
    verify(() => member.previewStartMemberships(any())).called(2);
    await cubit.close();
  });

  test('a solo run is the same path with one loop iteration', () async {
    final cubit = buildWizard(
      member: member,
      memberships: memberships,
      launchMember: detail(),
    );
    await cubit.open();
    expect(cubit.state.stepCount, 5, reason: '4 + N with N = 1');

    await cubit.next();
    cubit.togglePlan(soloPlan);
    await cubit.next();
    expect(cubit.state.step, MembershipWizardStep.reviewCharges);
    await cubit.close();
  });
}
