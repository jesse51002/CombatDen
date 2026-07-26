import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_consequence.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_cubit.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_step.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';

import 'membership_wizard_fixtures.dart';

/// The `who` step: the roster, the payer control, and the three moves that
/// used to destroy picked work in silence.
void main() {
  late MockMemberRepository member;
  late MockMembershipsRepository memberships;

  final unlimited = plan(planId: 'plan-a', priceId: 'price-a');
  final pack = plan(planId: 'plan-b', priceId: 'price-b');

  setUpAll(registerWizardFallbacks);

  setUp(() {
    member = MockMemberRepository();
    memberships = MockMembershipsRepository();
    when(() => member.listMembershipPlans(any()))
        .thenAnswer((_) async => [unlimited, pack]);
    when(() => member.listGymDiscounts(any())).thenAnswer((_) async => []);
    when(() => memberships.listMemberWaiverStatus(any(), any()))
        .thenAnswer((_) async => []);
  });

  Future<void> settle() async {
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  group('the family read', () {
    test('gathers every member CONCURRENTLY', () async {
      // Each read parks until BOTH have been asked for. A sequential walk —
      // the old wizard's `for` loop of awaits — would deadlock here, which is
      // exactly the assertion.
      final asked = <String>[];
      final gate = Completer<void>();
      when(() => member.getMemberDetail(any())).thenAnswer((call) async {
        final id = call.positionalArguments.first as String;
        asked.add(id);
        if (asked.length == 2) gate.complete();
        await gate.future;
        return detail(memberId: id, firstName: id);
      });

      final cubit = buildWizard(
        member: member,
        memberships: memberships,
        launchMember: detail(
          authorizedToPayFor: [
            linked(memberId: 'm-1'),
            linked(memberId: 'm-2'),
          ],
        ),
      );
      await cubit.open().timeout(const Duration(seconds: 2));
      expect(asked.toSet(), {'m-1', 'm-2'});
      expect(cubit.state.memberDetails.keys, containsAll(['m-1', 'm-2']));
      await cubit.close();
    });

    test('keeps a sibling answer when one member read fails', () async {
      when(() => member.getMemberDetail('m-1'))
          .thenThrow(const ServerException('boom', statusCode: 500));
      when(() => member.getMemberDetail('m-2'))
          .thenAnswer((_) async => detail(memberId: 'm-2'));

      final cubit = buildWizard(
        member: member,
        memberships: memberships,
        launchMember: detail(
          authorizedToPayFor: [
            linked(memberId: 'm-1'),
            linked(memberId: 'm-2'),
          ],
        ),
      );
      await cubit.open();
      expect(cubit.state.memberDetails.containsKey('m-1'), isFalse);
      expect(cubit.state.memberDetails.containsKey('m-2'), isTrue);
      // Fail-OPEN: no detail means no client-side gate, never a blocked grid.
      expect(cubit.state.gateFor('m-1', unlimited), isNull);
      await cubit.close();
    });
  });

  test('hands staff the FULL address, resolved from the detail read',
      () async {
    when(() => member.getMemberDetail('m-child')).thenAnswer(
      (_) async => detail(memberId: 'm-child', firstName: 'Ella'),
    );
    final cubit = buildWizard(
      member: member,
      memberships: memberships,
      launchMember: detail(authorizedToPayFor: [linked(memberId: 'm-child')]),
    );
    await cubit.open();

    // The authorization row carries only a name, so the address has to come
    // from the member's own detail — and this is the desk, so nothing masks it.
    final child = cubit.state.people.last;
    expect(child.memberId, 'm-child');
    expect(child.email, 'Ella@bell.family');
    expect(
      cubit.state.config.identity.identityLine(child.email),
      'Ella@bell.family',
    );
    await cubit.close();
  });

  group('the payer read', () {
    Future<MembershipWizardCubit> withPayerCandidate() async {
      final cubit = buildWizard(
        member: member,
        memberships: memberships,
        launchMember: detail(
          authorizedPayers: [linked(memberId: 'm-parent', firstName: 'Dana')],
        ),
      );
      when(() => member.getMemberDetail('m-parent')).thenAnswer(
        (_) async => detail(
          memberId: 'm-parent',
          firstName: 'Dana',
          authorizedToPayFor: [linked(memberId: 'm-payer', firstName: 'Marcus')],
        ),
      );
      await cubit.open();
      return cubit;
    }

    test('fails to a RETRYABLE error rather than an eternal spinner',
        () async {
      final cubit = await withPayerCandidate();
      when(() => member.getMemberDetail('m-parent'))
          .thenThrow(const ServerException('down', statusCode: 500));

      cubit.selectPayer('m-parent');
      await settle();

      expect(cubit.state.payerLoad.isFailed, isTrue);
      expect(cubit.state.payerLoad.message, isNotEmpty);
      expect(cubit.state.payerLoad.isLoading, isFalse);
      expect(
        cubit.state.canAdvance,
        isFalse,
        reason: 'the roster is unanswerable without it',
      );

      when(() => member.getMemberDetail('m-parent')).thenAnswer(
        (_) async => detail(
          memberId: 'm-parent',
          firstName: 'Dana',
          authorizedToPayFor: [linked(memberId: 'm-payer')],
        ),
      );
      await cubit.retryPayerDetail();
      expect(cubit.state.payerLoad.isReady, isTrue);
      expect(cubit.state.people.length, 2);
      await cubit.close();
    });

    test('switching the payer states what it drops', () async {
      final cubit = await withPayerCandidate();
      cubit.togglePlanFor('m-payer', unlimited);
      cubit.togglePlanFor('m-payer', pack);

      final forecast = cubit.consequenceOfPayerSwitch('m-parent');
      expect(forecast, isNotNull);
      expect(forecast!.kind, MembershipWizardConsequenceKind.payerSwitch);
      expect(forecast.membershipsDropped, 2);
      expect(forecast.destroys, isTrue);

      cubit.selectPayer('m-parent');
      await settle();

      expect(cubit.state.drafts, isEmpty);
      expect(cubit.state.trainingMemberIds, {'m-payer'});
      expect(cubit.state.payer.memberId, 'm-parent');
      expect(cubit.state.lastConsequence?.membershipsDropped, 2);
      cubit.clearConsequence();
      expect(cubit.state.lastConsequence, isNull);
      await cubit.close();
    });

    test('re-selecting the payer already paying changes nothing', () async {
      final cubit = await withPayerCandidate();
      expect(cubit.consequenceOfPayerSwitch('m-payer'), isNull);
      cubit.selectPayer('m-payer');
      expect(cubit.state.payer.memberId, 'm-payer');
      await cubit.close();
    });
  });

  group('the training tick', () {
    Future<MembershipWizardCubit> family() async {
      when(() => member.getMemberDetail('m-child'))
          .thenAnswer((_) async => detail(memberId: 'm-child'));
      final cubit = buildWizard(
        member: member,
        memberships: memberships,
        launchMember: detail(
          authorizedToPayFor: [linked(memberId: 'm-child')],
        ),
        initialTrainingMemberIds: const {'m-payer', 'm-child'},
      );
      await cubit.open();
      return cubit;
    }

    test('unticking states what it drops, and drops it', () async {
      final cubit = await family();
      cubit.togglePlanFor('m-child', unlimited);
      cubit.togglePlanFor('m-child', pack);

      final forecast = cubit.consequenceOfUntick('m-child');
      expect(forecast!.kind, MembershipWizardConsequenceKind.untickPerson);
      expect(forecast.membershipsDropped, 2);
      expect(forecast.peopleDropped, 1);

      cubit.setTraining('m-child', false);
      expect(cubit.state.drafts.containsKey('m-child'), isFalse);
      expect(cubit.state.trainingPeople.length, 1);
      expect(cubit.state.lastConsequence?.memberId, 'm-child');
      // They stay on the roster — the payer keeps paying, and re-ticking is
      // one tap rather than an "add somebody" round trip.
      expect(cubit.state.people.length, 2);
      await cubit.close();
    });

    test('unticking somebody with nothing picked carries no warning',
        () async {
      final cubit = await family();
      expect(cubit.consequenceOfUntick('m-child')!.membershipsDropped, 0);
      cubit.setTraining('m-child', false);
      expect(
        cubit.state.lastConsequence,
        isNull,
        reason: 'a warning nobody needs teaches staff to ignore the real ones',
      );
      await cubit.close();
    });

    test('re-ticking does NOT restore the dropped lineup', () async {
      final cubit = await family();
      cubit.togglePlanFor('m-child', unlimited);
      cubit.setTraining('m-child', false);
      cubit.setTraining('m-child', true);
      expect(cubit.state.draftsFor('m-child'), isEmpty);
      await cubit.close();
    });

    test('removing the last membership states that the person goes too',
        () async {
      final cubit = await family();
      cubit.togglePlanFor('m-child', unlimited);

      final forecast = cubit.consequenceOfRemoving('m-child', 'plan-a');
      expect(
        forecast!.kind,
        MembershipWizardConsequenceKind.removeMembership,
      );
      expect(forecast.membershipsDropped, 1);
      expect(forecast.peopleDropped, 1);

      cubit.removeMembership('m-child', 'plan-a');
      expect(cubit.state.trainingPeople.length, 1);
      expect(cubit.state.lastConsequence?.peopleDropped, 1);
      await cubit.close();
    });

    test('removing one of two memberships keeps the person in the run',
        () async {
      final cubit = await family();
      cubit.togglePlanFor('m-child', unlimited);
      cubit.togglePlanFor('m-child', pack);
      expect(cubit.consequenceOfRemoving('m-child', 'plan-a')!.peopleDropped, 0);

      cubit.removeMembership('m-child', 'plan-a');
      expect(cubit.state.draftsFor('m-child').length, 1);
      expect(cubit.state.trainingPeople.length, 2);
      await cubit.close();
    });
  });
}

/// Picks a plan for a NAMED person regardless of where the plans loop stands —
/// the roster tests are about the roster, not about walking to a step.
extension on MembershipWizardCubit {
  void togglePlanFor(String memberId, MembershipPlanResponse pick) {
    final at = state.trainingPeople
        .indexWhere((person) => person.memberId == memberId);
    expect(at, isNot(-1));
    goTo(MembershipWizardStep.plans, personIndex: at);
    togglePlan(pick);
  }
}
