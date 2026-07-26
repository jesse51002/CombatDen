import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_cubit.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_step.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/data/models/discount_type.dart';
import 'package:crm/features/member_details/data/models/discount_value.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';

import 'membership_wizard_fixtures.dart';

/// The plans step: the catalogue it may offer, the rules that close a card,
/// the pack stepper, and the discounts attached INLINE — no discounts step.
void main() {
  late MockMemberRepository member;
  late MockMembershipsRepository memberships;

  final unlimited = plan(planId: 'plan-a', priceId: 'price-a');
  final pack = plan(
    planId: 'plan-b',
    priceId: 'price-b',
    type: PlanType.oneTime,
    price: 5000,
    classCount: 5,
  );
  final trial = plan(
    planId: 'plan-t',
    priceId: 'price-t',
    type: PlanType.trial,
    price: 0,
  );
  final hidden = plan(planId: 'plan-h', priceId: 'price-h', isPublic: false);
  final unpriced = plan(planId: 'plan-u', priced: false);

  final familyPreset = DiscountResponse(
    discountId: 'disc-family',
    gymId: kGymId,
    discountName: 'Family 20%',
    discountType: DiscountType.preset,
    valueId: 'val-1',
    value: const DiscountValue(percentageOff: 20),
    createdAt: DateTime.utc(2026),
  );
  final tenOff = DiscountResponse(
    discountId: 'disc-ten',
    gymId: kGymId,
    discountName: r'$10 off',
    discountType: DiscountType.preset,
    valueId: 'val-2',
    value: const DiscountValue(dollarOff: 1000),
    createdAt: DateTime.utc(2026),
  );

  setUpAll(registerWizardFallbacks);

  setUp(() {
    member = MockMemberRepository();
    memberships = MockMembershipsRepository();
    when(() => member.listMembershipPlans(any()))
        .thenAnswer((_) async => [unlimited, pack, trial, hidden, unpriced]);
    when(() => member.listGymDiscounts(any()))
        .thenAnswer((_) async => [familyPreset, tenOff]);
    when(() => memberships.listMemberWaiverStatus(any(), any()))
        .thenAnswer((_) async => []);
  });

  Future<MembershipWizardCubit> soloWizard({
    List<dynamic> heldMemberships = const [],
  }) async {
    final cubit = buildWizard(
      member: member,
      memberships: memberships,
      launchMember: detail(memberships: heldMemberships.cast()),
    );
    await cubit.open();
    await cubit.next();
    return cubit;
  }

  test('offers only the plans the shared catalogue policy allows', () async {
    final cubit = await soloWizard();
    expect(
      cubit.state.plans.map((p) => p.planId),
      ['plan-a', 'plan-b', 'plan-t'],
      reason: 'a non-public or unpriced plan is not part of the offer',
    );
    await cubit.close();
  });

  test('a gate CLOSES a plan and a pick on it is refused', () async {
    final cubit = await soloWizard(
      heldMemberships: [held(planId: 'plan-a')],
    );
    final gate = cubit.state.gateFor('m-payer', unlimited);
    expect(gate, isNotNull);
    expect(gate!.reason, 'Already on this plan');

    cubit.togglePlan(unlimited);
    expect(cubit.state.currentDrafts, isEmpty);
    await cubit.close();
  });

  test('a past trial only ANNOTATES the card — staff may still grant one',
      () async {
    final cubit = await soloWizard(
      heldMemberships: [
        held(
          planId: 'plan-t',
          planType: 'trial',
          status: MembershipStatus.ended,
        ),
      ],
    );
    expect(cubit.state.gateFor('m-payer', trial), isNull);
    expect(
      cubit.state.notesFor('m-payer', trial).single.note,
      'Had this trial in the past',
    );

    cubit.togglePlan(trial);
    expect(cubit.state.currentDrafts.single.plan.planId, 'plan-t');
    await cubit.close();
  });

  test('an overdue recurring membership still blocks the same plan',
      () async {
    // `overdue` is a CLIENT display status masking the backend's raw `active`,
    // so it must block exactly as `active` does.
    final cubit = await soloWizard(
      heldMemberships: [
        held(planId: 'plan-a', status: MembershipStatus.overdue),
      ],
    );
    expect(cubit.state.gateFor('m-payer', unlimited), isNotNull);
    await cubit.close();
  });

  test('the pack stepper stacks a pack and is pinned to 1 for recurring',
      () async {
    final cubit = await soloWizard();
    cubit.togglePlan(pack);
    cubit.setQuantity('plan-b', 3);
    expect(cubit.state.currentDrafts.single.quantity, 3);

    cubit.togglePlan(unlimited);
    cubit.setQuantity('plan-a', 4);
    final recurring = cubit.state.currentDrafts
        .firstWhere((d) => d.plan.planId == 'plan-a');
    expect(
      recurring.quantity,
      1,
      reason: 'the DB refuses quantity > 1 on a recurring membership',
    );

    cubit.setQuantity('plan-b', 0);
    expect(
      cubit.state.currentDrafts
          .firstWhere((d) => d.plan.planId == 'plan-b')
          .quantity,
      1,
      reason: 'a membership of zero is a removal, and removal is its own '
          'control',
    );
    await cubit.close();
  });

  test('un-picking a plan drops its discounts with it', () async {
    final cubit = await soloWizard();
    cubit.togglePlan(unlimited);
    cubit.togglePresetDiscount('plan-a', 'disc-family');
    expect(cubit.state.currentDrafts.single.presetIds, {'disc-family'});

    cubit.togglePlan(unlimited);
    cubit.togglePlan(unlimited);
    expect(
      cubit.state.currentDrafts.single.presetIds,
      isEmpty,
      reason: 're-picking must not silently restore a discount nobody chose',
    );
    await cubit.close();
  });

  test('carries DIFFERENT discounts on different memberships in ONE '
      'submission', () async {
    final child = linked(memberId: 'm-child', firstName: 'Ella');
    when(() => member.getMemberDetail('m-child'))
        .thenAnswer((_) async => detail(memberId: 'm-child'));
    final cubit = buildWizard(
      member: member,
      memberships: memberships,
      launchMember: detail(authorizedToPayFor: [child]),
      initialTrainingMemberIds: const {'m-payer', 'm-child'},
    );
    await cubit.open();
    await cubit.next();

    // The payer: a recurring plan with the gym's family preset.
    cubit.togglePlan(unlimited);
    cubit.togglePresetDiscount('plan-a', 'disc-family');
    await cubit.next();

    // The child: two class packs — one on a different preset, one on an
    // inline one-off nobody else gets.
    cubit.togglePlan(pack);
    cubit.setQuantity('plan-b', 2);
    cubit.togglePresetDiscount('plan-b', 'disc-ten');
    cubit.togglePlan(trial);
    cubit.addCustomDiscount(
      'plan-t',
      const DiscountValue(percentageOff: 12.5, durationAmount: 1),
    );

    final items = cubit.state.pendingItems;
    expect(items.length, 3);

    expect(items[0].memberId, 'm-payer');
    expect(items[0].priceId, 'price-a');
    expect(items[0].quantity, 1);
    expect(items[0].discountIds, ['disc-family']);
    expect(items[0].customDiscounts, isEmpty);

    expect(items[1].memberId, 'm-child');
    expect(items[1].priceId, 'price-b');
    expect(items[1].quantity, 2);
    expect(items[1].discountIds, ['disc-ten']);

    expect(items[2].priceId, 'price-t');
    expect(items[2].discountIds, isEmpty);
    expect(items[2].customDiscounts.single.percentageOff, 12.5);
    await cubit.close();
  });

  test('an inline custom is appended, and removed by position', () async {
    final cubit = await soloWizard();
    cubit.togglePlan(pack);
    cubit.addCustomDiscount('plan-b', const DiscountValue(dollarOff: 500));
    cubit.addCustomDiscount('plan-b', const DiscountValue(dollarOff: 500));
    expect(
      cubit.state.currentDrafts.single.customs.length,
      2,
      reason: 'two identical one-offs are two real discounts',
    );

    cubit.removeCustomDiscount('plan-b', 0);
    expect(cubit.state.currentDrafts.single.customs.length, 1);

    // An index the list no longer holds must not take the dialog down.
    cubit.removeCustomDiscount('plan-b', 9);
    expect(cubit.state.currentDrafts.single.customs.length, 1);
    await cubit.close();
  });

  test('the desk config carries a discounts capability and an unbounded cart',
      () async {
    final cubit = await soloWizard();
    expect(cubit.state.config.discounts, isNotNull);
    expect(cubit.state.config.discounts!.offerablePresets.length, 2);
    expect(cubit.state.config.cart.maxPlansPerPerson, isNull);
    expect(cubit.state.config.cart.offersQuantity, isTrue);
    await cubit.close();
  });

  test('a cart change clears the staged preview', () async {
    when(() => member.previewStartMemberships(any()))
        .thenAnswer((_) async => startPreview(recurring: invoice()));
    final cubit = await soloWizard();
    cubit.togglePlan(unlimited);
    await cubit.next();
    expect(cubit.state.step, MembershipWizardStep.reviewCharges);
    expect(cubit.state.preview, isNotNull);

    cubit.editFromReview('m-payer');
    cubit.togglePlan(pack);
    expect(
      cubit.state.preview,
      isNull,
      reason: 'a stale figure beside a live cart quotes one number and '
          'charges another',
    );
    await cubit.close();
  });
}
